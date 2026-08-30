create or replace function app_trends(p_app_token uuid, p_parent_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today date;
  v_recent_minutes numeric;
  v_before_minutes numeric;
  v_before_days int;
  v_recent_missed int;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;
  v_today := (now() at time zone v_parent.timezone)::date;

  select avg(extract(epoch from (c.created_at at time zone v_parent.timezone)::time) / 60)
  into v_recent_minutes
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
  from generate_series(greatest(v_today - 29,
                                (v_parent.created_at at time zone v_parent.timezone)::date),
                       v_today - 1, '1 day') as d
  where not exists (select 1 from checkins c
                    where c.parent_id = v_parent.id and c.local_date = d::date);

  return jsonb_build_object(
    'recent_avg_minute', round(v_recent_minutes),
    'before_avg_minute', case when v_before_days >= 5 then round(v_before_minutes) end,
    'shift_minutes', case when v_recent_minutes is null or v_before_minutes is null
                            or v_before_days < 5
                          then null else round(v_recent_minutes - v_before_minutes) end,
    'missed_30d', v_recent_missed
  );
end $$;

revoke all on function app_trends(uuid, uuid) from public, anon, authenticated;
grant execute on function app_trends(uuid, uuid) to anon, authenticated;
