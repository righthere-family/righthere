alter table families add column app_token uuid not null default gen_random_uuid();
create unique index families_app_token_key on families (app_token);

revoke all on function parent_local_date(uuid)              from public, anon, authenticated;
revoke all on function record_checkin(bigint, text, text)   from public, anon, authenticated;
revoke all on function set_not_ok_detail(bigint, text, text) from public, anon, authenticated;
revoke all on function convert_to_accidental(bigint)        from public, anon, authenticated;
revoke all on function parents_due_for_morning()            from public, anon, authenticated;
revoke all on function parents_due_for_reping()             from public, anon, authenticated;
revoke all on function parents_past_deadline()              from public, anon, authenticated;
revoke all on function mark_morning_sent(uuid, boolean)     from public, anon, authenticated;
revoke all on function mark_reping_sent(uuid)               from public, anon, authenticated;
revoke all on function create_escalation(uuid)              from public, anon, authenticated;
revoke all on function find_invite(text)                    from public, anon, authenticated;
revoke all on function bind_invite(text, bigint)            from public, anon, authenticated;

create or replace function iso_utc(ts timestamptz)
returns text
language sql immutable as $$
  select to_char(ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
$$;

create or replace function app_snapshot(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family   families%rowtype;
  v_parent   parents%rowtype;
  v_today    date;
  v_checkin  checkins%rowtype;
  v_esc      escalations%rowtype;
  v_run      daily_runs%rowtype;
  v_anchor   date;
  v_streak   int := 0;
  v_status   jsonb;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  select * into v_parent
  from parents
  where family_id = v_family.id
  order by created_at
  limit 1;
  if not found then return null; end if;

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
  elsif v_esc.id is not null and v_esc.state in ('reping_sent', 'children_notified') then
    v_status := jsonb_build_object('state', 'quiet', 'at', iso_utc(v_esc.created_at));
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

  return jsonb_build_object(
    'parent', jsonb_build_object(
      'id',           v_parent.id,
      'kind',         v_parent.kind,
      'display_name', v_parent.display_name,
      'timezone',     v_parent.timezone,
      'checkin_time', to_char(v_parent.checkin_time, 'HH24:MI'),
      'window_min',   v_parent.window_min
    ),
    'status', v_status,
    'streak', v_streak
  );
end;
$$;

create or replace function app_month(p_app_token uuid, p_year int, p_month int)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_today  date;
  v_start  date;
  v_first  date;
  v_days   jsonb;
begin
  if p_month not between 1 and 12 or p_year not between 2020 and 2100 then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;

  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  select * into v_parent
  from parents
  where family_id = v_family.id
  order by created_at
  limit 1;
  if not found then return null; end if;

  v_today := (now() at time zone v_parent.timezone)::date;
  v_start := (v_parent.created_at at time zone v_parent.timezone)::date;
  v_first := make_date(p_year, p_month, 1);

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'day',   extract(day from d)::int,
    'mark',  case
               when d > v_today or d < v_start then 'upcoming'
               when c.status in ('ok', 'accidental_ok') then 'ok'
               when c.status = 'not_ok' then 'not_ok'
               when d = v_today then 'upcoming'
               else 'missed'
             end,
    'time',  case when c.status in ('ok', 'accidental_ok')
                  then to_char(c.created_at at time zone v_parent.timezone, 'HH24:MI') end,
    'quote', case when c.status = 'not_ok' then c.free_text end
  )) order by d), '[]'::jsonb)
  into v_days
  from generate_series(v_first, (v_first + interval '1 month' - interval '1 day')::date, '1 day') as d
  left join checkins c on c.parent_id = v_parent.id and c.local_date = d::date;

  return jsonb_build_object(
    'today', case when date_trunc('month', v_today::timestamp)::date = v_first
                  then extract(day from v_today)::int end,
    'days',  v_days
  );
end;
$$;

revoke all on function iso_utc(timestamptz)            from public, anon, authenticated;
revoke all on function app_snapshot(uuid)              from public, anon, authenticated;
revoke all on function app_month(uuid, int, int)       from public, anon, authenticated;
grant execute on function app_snapshot(uuid)           to anon, authenticated;
grant execute on function app_month(uuid, int, int)    to anon, authenticated;
