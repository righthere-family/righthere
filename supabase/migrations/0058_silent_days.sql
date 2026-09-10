create or replace function parent_silent_days(p_parent_id uuid, p_date date)
returns int
language sql stable as $$
  with days as (
    select (p_date - g)::date as d, g
    from generate_series(0, 365) as g
  ),
  marked as (
    select d.g,
           exists (select 1 from daily_runs r
                   where r.parent_id = p_parent_id and r.local_date = d.d
                     and r.morning_sent_at is not null) as asked,
           exists (select 1 from checkins c
                   where c.parent_id = p_parent_id and c.local_date = d.d) as answered
    from days d
  )
  select coalesce(min(g), 366)::int from marked where not asked or answered;
$$;

revoke all on function parent_silent_days(uuid, date) from public, anon, authenticated;

create or replace function record_checkin(
  p_telegram_user_id bigint,
  p_status text,
  p_source text
) returns jsonb
language plpgsql as $$
declare
  v_parent    parents%rowtype;
  v_today     date;
  v_existing  checkins%rowtype;
  v_escalated boolean := false;
  v_result    text := 'ok';
  v_streak    int := 0;
  v_milestone int;
  v_total     int := 0;
begin
  select * into v_parent from parents where telegram_user_id = p_telegram_user_id;
  if not found then
    return jsonb_build_object('result', 'unknown_parent');
  end if;

  v_today := (now() at time zone v_parent.timezone)::date;

  select * into v_existing from checkins
    where parent_id = v_parent.id and local_date = v_today;

  if found then
    if v_existing.status = 'not_ok' and p_status = 'ok' then
      update checkins
         set status = 'ok', source = p_source, not_ok_kind = null, free_text = null
       where id = v_existing.id;
      v_result := 'upgraded';
    elsif v_existing.status in ('ok', 'accidental_ok') and p_status = 'not_ok' then
      update checkins
         set status = 'not_ok', source = p_source, not_ok_kind = null, free_text = null
       where id = v_existing.id;
      v_result := 'worsened';
    else
      return jsonb_build_object('result', 'duplicate');
    end if;
  else
    begin
      insert into checkins (parent_id, local_date, status, source)
      values (v_parent.id, v_today, p_status, p_source);
    exception when unique_violation then
      return jsonb_build_object('result', 'duplicate');
    end;
  end if;

  update escalations
     set state = 'resolved_by_parent', resolved_at = now()
   where parent_id = v_parent.id
     and local_date = v_today
     and state in ('reping_sent', 'children_notified');
  v_escalated := found;

  select count(*) into v_streak from (
    select local_date, row_number() over (order by local_date desc) as rn
    from checkins
    where parent_id = v_parent.id
      and status in ('ok', 'accidental_ok')
      and local_date <= v_today
  ) t
  where t.local_date = v_today - (t.rn - 1)::int;

  select count(*) into v_total from checkins where parent_id = v_parent.id;

  if p_status = 'ok' and v_streak in (7, 30, 100, 365) then
    v_milestone := v_streak;
  end if;

  return jsonb_build_object(
    'result', v_result,
    'was_escalated', v_escalated,
    'streak', v_streak,
    'milestone', v_milestone,
    'first', v_result = 'ok' and v_total = 1,
    'silent_before', parent_silent_days(v_parent.id, v_today - 1),
    'parent_id', v_parent.id,
    'family_id', v_parent.family_id
  );
end $$;

revoke all on function record_checkin(bigint, text, text) from public, anon, authenticated;

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
              < (now() at time zone p.timezone)::date - 1

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
