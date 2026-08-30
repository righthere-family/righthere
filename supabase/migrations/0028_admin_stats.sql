create or replace function admin_stats()
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'stats', jsonb_build_object(
      'families',        (select count(*) from families),
      'parents_active',  (select count(*) from parents where bot_state = 'active'),
      'waitlist',        (select count(*) from waitlist),
      'stories',         (select count(*) from family_stories where answered_at is not null),
      'postcards',       (select count(*) from postcards where sent_at is not null),
      'checkins_today',  (select count(*) from checkins c join parents p on p.id = c.parent_id
                          where c.local_date = (now() at time zone p.timezone)::date),
      'checkins_7d',     (select count(*) from checkins where local_date > current_date - 7)
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
        'first_name', w.first_name,
        'username', w.username,
        'created_at', to_char(w.created_at, 'YYYY-MM-DD')
      ) order by w.created_at desc), '[]'::jsonb)
      from waitlist w
    )
  );
$$;

revoke all on function admin_stats() from public, anon, authenticated;
