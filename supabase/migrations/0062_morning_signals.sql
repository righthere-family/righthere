create index if not exists parent_messages_parent
  on parent_messages (parent_id, created_at desc);

create or replace function parent_signal(p_parent_id uuid, p_date date)
returns jsonb
language sql stable as $$
  with p as (
    select timezone from parents where id = p_parent_id
  ),
  signals as (
    select m.kind, m.created_at as at
    from parent_messages m, p
    where m.parent_id = p_parent_id
      and (m.created_at at time zone p.timezone)::date = p_date
    union all
    select 'med', coalesce(e.last_reminded_at, e.created_at)
    from med_events e
    join meds md on md.id = e.med_id
    where md.parent_id = p_parent_id
      and e.local_date = p_date
      and e.status = 'taken'
  )
  select jsonb_build_object('kind', kind, 'at', iso_utc(at))
  from signals
  order by at desc
  limit 1;
$$;

revoke all on function parent_signal(uuid, date) from public, anon, authenticated;

create or replace function parent_silent_days(p_parent_id uuid, p_date date)
returns int
language sql stable as $$
  with p as (
    select timezone from parents where id = p_parent_id
  ),
  heard as (
    select c.local_date as d from checkins c
    where c.parent_id = p_parent_id and c.local_date between p_date - 365 and p_date
    union
    select (m.created_at at time zone p.timezone)::date from parent_messages m, p
    where m.parent_id = p_parent_id and m.created_at >= (p_date - 366)::timestamp
    union
    select e.local_date from med_events e
    join meds md on md.id = e.med_id
    where md.parent_id = p_parent_id and e.status = 'taken'
      and e.local_date between p_date - 365 and p_date
  ),
  days as (
    select (p_date - g)::date as d, g
    from generate_series(0, 365) as g
  ),
  marked as (
    select d.g,
           exists (select 1 from daily_runs r
                   where r.parent_id = p_parent_id and r.local_date = d.d
                     and r.morning_sent_at is not null and r.delivery_ok) as asked,
           exists (select 1 from heard h where h.d = d.d) as answered
    from days d
  )
  select coalesce(min(g), 366)::int from marked where not asked or answered;
$$;

revoke all on function parent_silent_days(uuid, date) from public, anon, authenticated;

create or replace function app_parent_card(v_parent parents)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today   date;
  v_checkin checkins%rowtype;
  v_esc     escalations%rowtype;
  v_run     daily_runs%rowtype;
  v_anchor  date;
  v_streak  int := 0;
  v_status  jsonb;
  v_invite  text;
  v_meds_taken int := 0;
  v_meds_total int := 0;
  v_parent_json jsonb;
  v_evening jsonb;
begin
  v_parent_json := jsonb_build_object(
    'id',           v_parent.id,
    'kind',         v_parent.kind,
    'gender',       v_parent.gender,
    'display_name', v_parent.display_name,
    'city',         v_parent.city,
    'phone',        v_parent.phone,
    'timezone',     v_parent.timezone,
    'checkin_time', to_char(v_parent.checkin_time, 'HH24:MI'),
    'window_min',   v_parent.window_min,
    'evening_time', to_char(v_parent.evening_time, 'HH24:MI'),
    'lang',         v_parent.lang
  );

  if v_parent.telegram_user_id is null then
    select code into v_invite
    from invites
    where parent_id = v_parent.id and bound_at is null and expires_at > now()
    order by expires_at desc
    limit 1;

    return jsonb_build_object(
      'parent',      v_parent_json,
      'status',      jsonb_build_object('state', 'waiting_parent'),
      'streak',      0,
      'meds',        jsonb_build_object('taken', 0, 'total', 0),
      'invite_code', v_invite
    );
  end if;

  v_today := (now() at time zone v_parent.timezone)::date;

  select * into v_checkin from checkins    where parent_id = v_parent.id and local_date = v_today;
  select * into v_esc     from escalations where parent_id = v_parent.id and local_date = v_today;
  select * into v_run     from daily_runs  where parent_id = v_parent.id and local_date = v_today;

  v_anchor := case when v_checkin.id is null then v_today - 1 else v_today end;
  select count(*) into v_streak from (
    select local_date, row_number() over (order by local_date desc) as rn
    from checkins
    where parent_id = v_parent.id
      and status in ('ok', 'accidental_ok')
      and local_date <= v_anchor
  ) t
  where t.local_date = v_anchor - (t.rn - 1)::int;

  select coalesce(sum(cardinality(m.times)), 0) into v_meds_total
  from meds m
  where m.parent_id = v_parent.id and m.active
    and extract(isodow from v_today)::int = any(m.days);

  select count(*) into v_meds_taken
  from med_events e
  join meds m on m.id = e.med_id
  where m.parent_id = v_parent.id
    and e.local_date = v_today
    and e.status = 'taken';

  if v_parent.bot_state = 'paused' and v_parent.paused_until is not null
     and v_parent.paused_until >= v_today then
    v_status := jsonb_build_object('state', 'paused', 'until', to_char(v_parent.paused_until, 'YYYY-MM-DD'));
  elsif v_checkin.id is not null and v_checkin.status in ('ok', 'accidental_ok') then
    v_status := jsonb_build_object('state', 'ok', 'at', iso_utc(v_checkin.created_at));
  elsif v_checkin.id is not null then
    v_status := jsonb_build_object(
      'state', 'not_ok',
      'at',    iso_utc(v_checkin.created_at),
      'kind',  v_checkin.not_ok_kind,
      'quote', v_checkin.free_text
    );
  elsif v_parent.bot_state = 'blocked' then
    v_status := jsonb_build_object('state', 'blocked');
  elsif v_esc.id is not null and v_esc.state in ('reping_sent', 'children_notified') then
    v_status := jsonb_build_object(
      'state',  'quiet',
      'at',     iso_utc(v_esc.created_at),
      'signal', parent_signal(v_parent.id, v_today)
    );
  elsif v_run.reping_sent_at is not null then
    v_status := jsonb_build_object(
      'state',    'reminded',
      'at',       iso_utc(v_run.reping_sent_at),
      'deadline', iso_utc((v_today::timestamp + v_parent.checkin_time
                           + make_interval(mins => v_parent.window_min)) at time zone v_parent.timezone)
    );
  else
    v_status := jsonb_build_object(
      'state',    'still_morning',
      'usual_by', iso_utc((v_today::timestamp + v_parent.checkin_time) at time zone v_parent.timezone)
    );
  end if;

  if v_checkin.evening_status is not null then
    v_evening := jsonb_build_object(
      'status', v_checkin.evening_status,
      'at',     iso_utc(v_checkin.evening_at)
    );
  end if;

  return jsonb_build_object(
    'parent',  v_parent_json,
    'status',  v_status,
    'streak',  v_streak,
    'meds',    jsonb_build_object('taken', v_meds_taken, 'total', v_meds_total),
    'evening', v_evening,
    'week', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'date', to_char(d, 'YYYY-MM-DD'),
        'mark', coalesce(
          (select case when c.status in ('ok', 'accidental_ok') then 'ok' else 'alert' end
             from checkins c
            where c.parent_id = v_parent.id and c.local_date = d::date),
          case when d::date = v_today then 'pending' else 'none' end)
      ) order by d), '[]'::jsonb)
      from generate_series(v_today - 6, v_today, '1 day') d
    )
  );
end $$;
