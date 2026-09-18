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
    'missed_30d',        case when v_start <= v_today - 7 then v_recent_missed end
  );
end $$;

revoke all on function app_trends(uuid, uuid) from public, anon, authenticated;
grant execute on function app_trends(uuid, uuid) to anon, authenticated;
