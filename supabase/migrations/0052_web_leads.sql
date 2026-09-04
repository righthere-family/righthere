create table if not exists web_leads (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  mom_channel text check (mom_channel in ('telegram', 'whatsapp', 'sms', 'unknown')),
  lang text not null default 'ru' check (lang in ('ru', 'en')),
  source text not null default 'landing',
  created_at timestamptz not null default now(),
  invited_at timestamptz
);

create unique index if not exists web_leads_email on web_leads (lower(email));

alter table web_leads enable row level security;

create or replace function admin_stats()
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'stats', jsonb_build_object(
      'families',        (select count(*) from families),
      'parents_active',  (select count(*) from parents where bot_state = 'active'),
      'waitlist',        (select count(*) from waitlist),
      'web_leads',       (select count(*) from web_leads),
      'stories',         (select count(*) from family_stories where answered_at is not null),
      'postcards',       (select count(*) from postcards where sent_at is not null),
      'checkins_today',  (select count(*) from checkins c join parents p on p.id = c.parent_id
                          where c.local_date = (now() at time zone p.timezone)::date),
      'checkins_7d',     (select count(*) from checkins where local_date > current_date - 7),
      'errors_24h',      (select count(*) from bot_events where at > now() - interval '24 hours')
    ),
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'date', to_char(d, 'DD.MM'),
        'ok',      (select count(*) from checkins c
                    where c.local_date = d::date and c.status in ('ok','accidental_ok')),
        'not_ok',  (select count(*) from checkins c
                    where c.local_date = d::date and c.status = 'not_ok')
      ) order by d), '[]'::jsonb)
      from generate_series(current_date - 13, current_date, '1 day') as d
    ),
    'attention', (
      select coalesce(jsonb_agg(a.item order by a.ord), '[]'::jsonb)
      from (
        select 1 as ord, jsonb_build_object(
          'kind', 'undelivered',
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1)
        ) as item
        from daily_runs r
        join parents p on p.id = r.parent_id
        where r.local_date = (now() at time zone p.timezone)::date
          and not r.delivery_ok

        union all

        select 2, jsonb_build_object(
          'kind', p.bot_state,
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1)
        )
        from parents p
        where p.bot_state in ('blocked', 'stopped')

        union all

        select 3, jsonb_build_object(
          'kind', 'silent',
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1),
          'days', (now() at time zone p.timezone)::date
                  - (select max(c.local_date) from checkins c where c.parent_id = p.id)
        )
        from parents p
        where p.bot_state = 'active'
          and p.telegram_user_id is not null
          and (select max(c.local_date) from checkins c where c.parent_id = p.id)
              < (now() at time zone p.timezone)::date - 2

        union all

        select 4, jsonb_build_object(
          'kind', 'unlinked',
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1)
        )
        from parents p
        where p.telegram_user_id is null
          and p.created_at < now() - interval '3 days'
      ) a
    ),
    'events', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'at', to_char(e.at, 'DD.MM HH24:MI'),
        'level', e.level,
        'kind', e.kind,
        'detail', left(e.detail, 300)
      ) order by e.at desc), '[]'::jsonb)
      from (select * from bot_events order by at desc limit 30) e
    ),
    'families', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id,
        'created_at', to_char(f.created_at, 'YYYY-MM-DD'),
        'child', (select m.display_name from family_members m
                  where m.family_id = f.id and m.role = 'owner' limit 1),
        'members', (select count(*) from family_members m where m.family_id = f.id),
        'stories', (select count(*) from family_stories s
                    where s.family_id = f.id and s.answered_at is not null),
        'parents', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'display_name', p.display_name,
            'city', p.city,
            'lang', p.lang,
            'bot_state', p.bot_state,
            'checkin_time', to_char(p.checkin_time, 'HH24:MI'),
            'evening_time', to_char(p.evening_time, 'HH24:MI'),
            'last_date', (select to_char(c.local_date, 'DD.MM') from checkins c
                          where c.parent_id = p.id order by c.local_date desc limit 1),
            'last_status', (select c.status from checkins c
                            where c.parent_id = p.id order by c.local_date desc limit 1),
            'streak', (
              select count(*) from (
                select c.local_date, row_number() over (order by c.local_date desc) as rn
                from checkins c
                where c.parent_id = p.id and c.status in ('ok','accidental_ok')
              ) t
              where t.local_date = (select max(c2.local_date) from checkins c2
                                    where c2.parent_id = p.id
                                      and c2.status in ('ok','accidental_ok')) - (t.rn - 1)::int
            )
          ) order by p.created_at), '[]'::jsonb)
          from parents p where p.family_id = f.id
        )
      ) order by f.created_at), '[]'::jsonb)
      from families f
    ),
    'waitlist', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'telegram_user_id', w.telegram_user_id,
        'first_name', w.first_name,
        'username', w.username,
        'lang', w.lang,
        'mom_channel', w.mom_channel,
        'created_at', to_char(w.created_at, 'YYYY-MM-DD'),
        'invited_at', to_char(w.invited_at, 'DD.MM.YYYY')
      ) order by w.created_at desc), '[]'::jsonb)
      from waitlist w
    ),
    'web_leads', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id,
        'email', l.email,
        'mom_channel', l.mom_channel,
        'lang', l.lang,
        'created_at', to_char(l.created_at, 'YYYY-MM-DD'),
        'invited_at', to_char(l.invited_at, 'DD.MM.YYYY')
      ) order by l.created_at desc), '[]'::jsonb)
      from web_leads l
    )
  );
$$;

revoke all on function admin_stats() from public, anon, authenticated;
