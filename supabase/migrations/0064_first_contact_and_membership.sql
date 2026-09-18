create or replace function parent_start_date(p_parent_id uuid)
returns date
language sql stable as $$
  select coalesce(
    least(
      (select (min(i.bound_at) at time zone p.timezone)::date
         from invites i where i.parent_id = p.id and i.bound_at is not null),
      (select min(c.local_date) from checkins c where c.parent_id = p.id)
    ),
    (p.created_at at time zone p.timezone)::date
  )
  from parents p
  where p.id = p_parent_id;
$$;

revoke all on function parent_start_date(uuid) from public, anon, authenticated;

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
           p.lang                              as lang,
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
           parent_start_date(a.parent_id)                   as started_on
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
           t.window_min, t.timezone, t.child_display_name, t.lang,
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
           t.window_min, t.timezone, t.child_display_name, t.lang, t.local_date
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
           t.window_min, t.timezone, t.child_display_name, t.lang, r.local_date
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
           t.address_form, t.display_name, t.lang,
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
           t.address_form, t.display_name, t.lang,
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
           c.author_name, c.body, c.photo_path, t.lang, c.created_at
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
           t.address_form, t.display_name, t.lang, t.local_date
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
           t.address_form, t.display_name, t.lang, t.week_start
    from today t
    where t.telegram_user_id is not null
      and t.started_on <= t.local_date - 7
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
           t.child_display_name, t.lang,
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
        'lang',               d.lang,
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
        'lang',               m.lang,
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
        'lang',               r.lang,
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
        'lang',             x.lang,
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
        'photo_path',       c.photo_path,
        'lang',             c.lang
      ) order by c.created_at) from due_postcards c
    ), '[]'::jsonb),

    'evening', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',        e.parent_id,
        'family_id',        e.family_id,
        'telegram_user_id', e.telegram_user_id,
        'address_form',     e.address_form,
        'display_name',     e.display_name,
        'lang',             e.lang,
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
        'lang',             y.lang,
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
        'lang',               g.lang,
        'ok_days',            g.ok_days,
        'covered_days',       g.covered_days,
        'week_start',         g.week_start
      )) from due_digest g
    ), '[]'::jsonb)
  )
  from snap s;
$$;

revoke all on function cron_due() from public, anon, authenticated;

create or replace function app_month(
  p_app_token uuid,
  p_year int,
  p_month int,
  p_parent_id uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today  date;
  v_start  date;
  v_first  date;
  v_archived date;
  v_days   jsonb;
begin
  if p_month not between 1 and 12 or p_year not between 2020 and 2100 then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;

  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;

  v_today := (now() at time zone v_parent.timezone)::date;
  if make_date(p_year, p_month, 1) < date_trunc('month', v_today)::date
     and family_entitlement(p_app_token) is null then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;
  v_start := parent_start_date(v_parent.id);
  v_archived := (v_parent.archived_at at time zone v_parent.timezone)::date;
  v_first := make_date(p_year, p_month, 1);

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'day',   extract(day from d)::int,
    'mark',  case
               when d > v_today or d < v_start then 'upcoming'
               when c.status in ('ok', 'accidental_ok') then 'ok'
               when c.status = 'not_ok' then 'not_ok'
               when v_archived is not null and d >= v_archived then 'off'
               when exists (select 1 from parent_pauses x
                            where x.parent_id = v_parent.id
                              and d::date between x.starts_on and x.ends_on) then 'paused'
               when d = v_today then 'today'
               when r.morning_sent_at is not null and r.delivery_ok then 'missed'
               else 'off'
             end,
    'time',  case when c.status in ('ok', 'accidental_ok')
                  then to_char(c.created_at at time zone v_parent.timezone, 'HH24:MI') end,
    'quote', case when c.status = 'not_ok' then c.free_text end
  )) order by d), '[]'::jsonb)
  into v_days
  from generate_series(v_first, (v_first + interval '1 month' - interval '1 day')::date, '1 day') as d
  left join checkins c on c.parent_id = v_parent.id and c.local_date = d::date
  left join daily_runs r on r.parent_id = v_parent.id and r.local_date = d::date;

  return jsonb_build_object(
    'today', case when date_trunc('month', v_today::timestamp)::date = v_first
                  then extract(day from v_today)::int end,
    'days',  v_days
  );
end;
$$;

create or replace function app_trends(p_app_token uuid, p_parent_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today date;
  v_start date;
  v_first date;
  v_recent_minutes numeric;
  v_recent_days int;
  v_before_minutes numeric;
  v_before_days int;
  v_recent_missed int;
  v_mature boolean;
  v_enough boolean;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;
  v_today := (now() at time zone v_parent.timezone)::date;
  v_start := parent_start_date(v_parent.id);

  select min(c.local_date) into v_first
  from checkins c
  where c.parent_id = v_parent.id
    and c.status in ('ok', 'accidental_ok');

  select avg(extract(epoch from (c.created_at at time zone v_parent.timezone)::time) / 60),
         count(distinct c.local_date)
  into v_recent_minutes, v_recent_days
  from checkins c
  where c.parent_id = v_parent.id
    and c.status in ('ok', 'accidental_ok')
    and c.local_date >= v_today - 13 and c.local_date <= v_today;

  select avg(extract(epoch from (c.created_at at time zone v_parent.timezone)::time) / 60),
         count(distinct c.local_date)
  into v_before_minutes, v_before_days
  from checkins c
  where c.parent_id = v_parent.id
    and c.status in ('ok', 'accidental_ok')
    and c.local_date >= v_today - 43 and c.local_date < v_today - 13;

  select count(*) into v_recent_missed
  from daily_runs r
  where r.parent_id = v_parent.id
    and r.local_date between greatest(v_today - 29, v_start) and v_today - 1
    and r.morning_sent_at is not null
    and r.delivery_ok
    and not exists (select 1 from checkins c
                    where c.parent_id = v_parent.id and c.local_date = r.local_date);

  v_enough := v_recent_days >= 5;
  v_mature := v_enough and v_before_days >= 10 and v_first is not null and v_first <= v_today - 35;

  return jsonb_build_object(
    'recent_avg_minute', case when v_enough then round(v_recent_minutes) end,
    'before_avg_minute', case when v_mature then round(v_before_minutes) end,
    'shift_minutes',     case when v_mature then round(v_recent_minutes - v_before_minutes) end,
    'missed_30d',        case when v_enough then v_recent_missed end
  );
end $$;

revoke all on function app_trends(uuid, uuid) from public, anon, authenticated;
grant execute on function app_trends(uuid, uuid) to anon, authenticated;

create or replace function family_join_caller(p_family_id uuid, p_timezone text default null)
returns family_members
language plpgsql as $$
declare
  v_member family_members%rowtype;
begin
  if auth.uid() is null then
    return v_member;
  end if;
  insert into family_members (family_id, user_id, role, display_name, timezone)
  values (p_family_id, auth.uid(), 'sibling', '', coalesce(nullif(trim(p_timezone), ''), 'UTC'))
  on conflict (family_id, user_id) do nothing;
  select * into v_member from family_members
  where family_id = p_family_id and user_id = auth.uid();
  return v_member;
end $$;

revoke all on function family_join_caller(uuid, text) from public, anon, authenticated;

create or replace function app_join_family(p_app_token uuid, p_timezone text default null)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_member family_members%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;
  v_member := family_join_caller(v_family.id, p_timezone);
  return v_member.role;
end $$;

revoke all on function app_join_family(uuid, text) from public, anon, authenticated;
grant execute on function app_join_family(uuid, text) to anon, authenticated;

create or replace function app_send_postcard(
  p_app_token uuid,
  p_parent_id uuid,
  p_body text,
  p_photo_path text default null
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_member family_members%rowtype;
  v_body   text;
begin
  v_body := trim(coalesce(p_body, ''));
  if (v_body = '' and p_photo_path is null) or length(v_body) > 500 then
    return false;
  end if;

  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  if p_photo_path is not null then
    if p_photo_path like 'kv\_%' then
      if p_photo_path !~ '^kv_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        return false;
      end if;
    elsif not exists (
      select 1 from postcard_blobs
      where id::text = p_photo_path and family_id = v_family.id
    ) then
      return false;
    end if;
  end if;

  if not exists (select 1 from parents
                 where id = p_parent_id and family_id = v_family.id
                   and telegram_user_id is not null) then
    return false;
  end if;

  v_member := family_join_caller(v_family.id);
  if v_member.user_id is null then
    return false;
  end if;

  insert into postcards (family_id, parent_id, author_name, body, photo_path)
  values (v_family.id, p_parent_id, coalesce(v_member.display_name, ''), v_body, p_photo_path);
  return true;
end $$;
