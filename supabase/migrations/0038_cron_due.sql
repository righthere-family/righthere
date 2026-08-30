do $$
begin

  if not exists (
       select 1 from parents
       where checkin_time < time '04:00' or checkin_time > time '23:15'
     )
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'parents'::regclass
         and conname = 'parents_checkin_time_in_day'
     )
  then
    alter table parents
      add constraint parents_checkin_time_in_day
      check (checkin_time >= time '04:00' and checkin_time <= time '23:15');
  end if;

  if not exists (
       select 1 from parents
       where evening_time is not null
         and (evening_time < time '12:00' or evening_time >= time '23:00')
     )
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'parents'::regclass
         and conname = 'parents_evening_time_before_night'
     )
  then
    alter table parents
      add constraint parents_evening_time_before_night
      check (evening_time is null
             or (evening_time >= time '12:00' and evening_time < time '23:00'));
  end if;
end $$;

create or replace function cron_due()
returns jsonb
language sql stable security definer set search_path = public as $$

  with snap as (
    select now() as at
  ),

  active as (
    select p.id                                as parent_id,
           p.family_id                         as family_id,
           p.telegram_user_id                  as telegram_user_id,
           p.display_name                      as display_name,
           p.address_form                      as address_form,
           p.checkin_time                      as checkin_time,
           p.window_min                        as window_min,
           p.timezone                          as timezone,
           p.evening_time                      as evening_time,
           p.paused_until                      as paused_until,
           p.created_at                        as created_at,
           coalesce(o.display_name, '')        as child_display_name,
           s.at                                as at,
           (s.at at time zone p.timezone)      as local_ts
    from snap s
    cross join parents p
    left join lateral (
      select fm.display_name from family_members fm
      where fm.family_id = p.family_id and fm.role = 'owner'
      limit 1
    ) o on true
    where p.bot_state = 'active'
  ),

  clock as (
    select a.*,
           a.local_ts::date                                  as local_date,
           a.local_ts::time                                  as local_time,
           extract(isodow from a.local_ts)::int              as local_dow,
           date_trunc('week', a.local_ts)::date              as week_start,
           (a.created_at at time zone a.timezone)::date      as started_on
    from active a
  ),

  today as (
    select c.*,
           (c.local_date::timestamp + c.checkin_time) at time zone c.timezone as checkin_at,
           case when c.evening_time is not null
                then (c.local_date::timestamp + c.evening_time) at time zone c.timezone
           end                                                                as evening_at
    from clock c
  ),

  due_deadline as (
    select distinct on (t.parent_id)
           t.parent_id, t.family_id, t.telegram_user_id,
           t.display_name, t.address_form, t.checkin_time,
           t.window_min, t.timezone, t.child_display_name,
           r.local_date as local_date
    from today t
    join daily_runs r
      on r.parent_id = t.parent_id
     and r.local_date between t.local_date - 1 and t.local_date
    cross join lateral (
      select (r.local_date::timestamp + t.checkin_time
              + make_interval(mins => t.window_min)) at time zone t.timezone as deadline_at
    ) d
    where r.morning_sent_at is not null
      and r.delivery_ok
      and t.at >= d.deadline_at
      and t.at <  d.deadline_at + interval '12 hours'
      and not exists (
        select 1 from checkins c
        where c.parent_id = t.parent_id and c.local_date >= r.local_date
      )

      and not exists (
        select 1 from escalations e
        where e.parent_id = t.parent_id and e.local_date = r.local_date
      )
    order by t.parent_id, r.local_date desc
  ),

  due_morning as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.display_name, t.address_form, t.checkin_time,
           t.window_min, t.timezone, t.child_display_name, t.local_date
    from today t
    where t.telegram_user_id is not null
      and (t.paused_until is null or t.paused_until < t.local_date)
      and t.at >= t.checkin_at

      and t.at <  t.checkin_at + make_interval(mins => t.window_min)
      and not exists (
        select 1 from checkins c
        where c.parent_id = t.parent_id and c.local_date = t.local_date
      )
      and not exists (
        select 1 from daily_runs r
        where r.parent_id = t.parent_id
          and r.local_date = t.local_date
          and r.morning_sent_at is not null
      )
  ),

  due_reping as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.display_name, t.address_form, t.checkin_time,
           t.window_min, t.timezone, t.child_display_name, r.local_date
    from today t
    join daily_runs r
      on r.parent_id = t.parent_id
     and r.local_date = t.local_date
    where r.morning_sent_at is not null
      and r.delivery_ok
      and r.reping_sent_at is null
      and r.morning_sent_at <= t.at - interval '90 minutes'
      and not exists (
        select 1 from checkins c
        where c.parent_id = t.parent_id and c.local_date = r.local_date
      )
  ),

  due_meds as (

    select t.telegram_user_id, t.family_id,
           m.id    as med_id,
           m.title as med_title,
           s.slot  as slot,
           t.address_form, t.display_name,
           false   as is_repeat,
           t.local_date
    from today t
    join meds m on m.parent_id = t.parent_id and m.active
    cross join lateral unnest(m.times) as s(slot)
    cross join lateral (
      select (t.local_date::timestamp + s.slot) at time zone t.timezone as slot_at
    ) k
    where t.telegram_user_id is not null
      and t.local_dow = any(m.days)
      and t.at >= k.slot_at
      and t.at <  k.slot_at + interval '2 hours'
      and (t.at < k.slot_at + interval '90 minutes'
           or (t.local_time >= time '08:00' and t.local_time < time '23:00'))
      and not exists (
        select 1 from med_events e
        where e.med_id = m.id
          and e.local_date = t.local_date
          and e.slot = s.slot
      )
    union all

    select t.telegram_user_id, t.family_id,
           m.id, m.title, e.slot,
           t.address_form, t.display_name,
           true,
           e.local_date
    from today t
    join meds m on m.parent_id = t.parent_id
    join med_events e on e.med_id = m.id
    cross join lateral (
      select (e.local_date::timestamp + e.slot) at time zone t.timezone as slot_at
    ) k
    where t.telegram_user_id is not null
      and e.status = 'postponed'
      and e.remind_count < 3
      and e.local_date between t.local_date - 1 and t.local_date
      and t.at >= e.last_reminded_at + interval '30 minutes'
      and t.at <  e.last_reminded_at + interval '2 hours'
      and (t.at < k.slot_at + interval '90 minutes'
           or (t.local_time >= time '08:00' and t.local_time < time '23:00'))
  ),

  due_postcards as (
    select c.id as postcard_id, c.family_id, t.telegram_user_id,
           c.author_name, c.body, c.photo_path, c.created_at
    from postcards c
    join today t on t.parent_id = c.parent_id
    where c.sent_at is null
      and t.telegram_user_id is not null
      and t.local_time >= time '08:00'
      and t.local_time <  time '23:00'
    order by c.created_at
    limit 20
  ),

  due_evening as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.address_form, t.display_name, t.local_date
    from today t
    where t.telegram_user_id is not null
      and t.evening_at is not null
      and t.at >= t.evening_at
      and t.at <  t.evening_at + interval '2 hours'
      and (t.at < t.evening_at + interval '10 minutes'
           or t.local_time < time '23:00')
      and not exists (
        select 1 from daily_runs r
        where r.parent_id = t.parent_id
          and r.local_date = t.local_date
          and r.evening_sent_at is not null
      )
  ),

  due_story as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.address_form, t.display_name, t.week_start
    from today t
    where t.telegram_user_id is not null
      and t.created_at < t.at - interval '7 days'
      and t.local_dow = 6
      and t.local_time >= time '12:00'
      and t.local_time <  time '22:00'
      and not exists (
        select 1 from family_stories s
        where s.parent_id = t.parent_id and s.week_start = t.week_start
      )
  ),

  due_digest as (
    select t.parent_id, t.telegram_user_id, t.address_form, t.display_name,
           t.child_display_name,
           (select count(*)::int from checkins c
             where c.parent_id = t.parent_id
               and c.local_date between t.week_start and t.local_date
               and c.status in ('ok', 'accidental_ok'))            as ok_days,
           (t.local_date - greatest(t.week_start, t.started_on) + 1)::int as covered_days,
           t.week_start
    from today t
    where t.telegram_user_id is not null
      and t.local_dow = 7
      and t.local_time >= time '19:00'
      and t.local_time <  time '23:00'
      and not exists (
        select 1 from parent_digests pd
        where pd.parent_id = t.parent_id and pd.week_start = t.week_start
      )

      and t.local_date - greatest(t.week_start, t.started_on) + 1 >= 3
  )

  select jsonb_build_object(
    'at', iso_utc(s.at),

    'deadline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          d.parent_id,
        'family_id',          d.family_id,
        'telegram_user_id',   d.telegram_user_id,
        'display_name',       d.display_name,
        'address_form',       d.address_form,
        'checkin_time',       d.checkin_time,
        'window_min',         d.window_min,
        'tz',                 d.timezone,
        'child_display_name', d.child_display_name,
        'local_date',         d.local_date
      )) from due_deadline d
    ), '[]'::jsonb),

    'morning', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          m.parent_id,
        'family_id',          m.family_id,
        'telegram_user_id',   m.telegram_user_id,
        'display_name',       m.display_name,
        'address_form',       m.address_form,
        'checkin_time',       m.checkin_time,
        'window_min',         m.window_min,
        'tz',                 m.timezone,
        'child_display_name', m.child_display_name,
        'local_date',         m.local_date
      )) from due_morning m
    ), '[]'::jsonb),

    'reping', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          r.parent_id,
        'family_id',          r.family_id,
        'telegram_user_id',   r.telegram_user_id,
        'display_name',       r.display_name,
        'address_form',       r.address_form,
        'checkin_time',       r.checkin_time,
        'window_min',         r.window_min,
        'tz',                 r.timezone,
        'child_display_name', r.child_display_name,
        'local_date',         r.local_date
      )) from due_reping r
    ), '[]'::jsonb),

    'meds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'telegram_user_id', x.telegram_user_id,
        'family_id',        x.family_id,
        'med_id',           x.med_id,
        'med_title',        x.med_title,
        'slot',             x.slot,
        'address_form',     x.address_form,
        'display_name',     x.display_name,
        'is_repeat',        x.is_repeat,
        'local_date',       x.local_date
      )) from due_meds x
    ), '[]'::jsonb),

    'postcards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'postcard_id',      c.postcard_id,
        'family_id',        c.family_id,
        'telegram_user_id', c.telegram_user_id,
        'author_name',      c.author_name,
        'body',             c.body,
        'photo_path',       c.photo_path
      ) order by c.created_at) from due_postcards c
    ), '[]'::jsonb),

    'evening', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',        e.parent_id,
        'family_id',        e.family_id,
        'telegram_user_id', e.telegram_user_id,
        'address_form',     e.address_form,
        'display_name',     e.display_name,
        'local_date',       e.local_date
      )) from due_evening e
    ), '[]'::jsonb),

    'story', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',        y.parent_id,
        'family_id',        y.family_id,
        'telegram_user_id', y.telegram_user_id,
        'address_form',     y.address_form,
        'display_name',     y.display_name,
        'week_start',       y.week_start
      )) from due_story y
    ), '[]'::jsonb),

    'digest', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          g.parent_id,
        'telegram_user_id',   g.telegram_user_id,
        'address_form',       g.address_form,
        'display_name',       g.display_name,
        'child_display_name', g.child_display_name,
        'ok_days',            g.ok_days,
        'covered_days',       g.covered_days,
        'week_start',         g.week_start
      )) from due_digest g
    ), '[]'::jsonb)
  )
  from snap s;
$$;

revoke all on function cron_due() from public, anon, authenticated;
