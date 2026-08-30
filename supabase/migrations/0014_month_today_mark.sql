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
               when d = v_today then 'today'
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

revoke all on function app_month(uuid, int, int)    from public, anon, authenticated;
grant execute on function app_month(uuid, int, int) to anon, authenticated;
