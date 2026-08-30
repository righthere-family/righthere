drop function if exists app_month(uuid, int, int);
drop function if exists app_meds(uuid);
drop function if exists app_med_add(uuid, text, time[]);

create or replace function app_parent_for(p_app_token uuid, p_parent_id uuid)
returns parents
language sql stable security definer set search_path = public as $$
  select p.*
  from parents p
  join families f on f.id = p.family_id
  where f.app_token = p_app_token
    and (p_parent_id is null or p.id = p_parent_id)
  order by p.created_at
  limit 1;
$$;

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
  v_days   jsonb;
begin
  if p_month not between 1 and 12 or p_year not between 2020 and 2100 then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;

  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;

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

create or replace function app_meds(p_app_token uuid, p_parent_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', m.id,
      'title', m.title,
      'times', (select jsonb_agg(to_char(t, 'HH24:MI') order by t) from unnest(m.times) as t)
    ) order by m.created_at)
    from meds m
    where m.parent_id = v_parent.id and m.active
  ), '[]'::jsonb);
end $$;

create or replace function app_med_add(
  p_app_token uuid,
  p_title text,
  p_times time[],
  p_parent_id uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_med meds%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;
  if nullif(trim(p_title), '') is null or cardinality(p_times) = 0 then
    return null;
  end if;

  insert into meds (parent_id, title, human_text, times)
  values (v_parent.id, trim(p_title), trim(p_title), p_times)
  returning * into v_med;

  return jsonb_build_object('id', v_med.id);
end $$;

revoke all on function app_parent_for(uuid, uuid)                from public, anon, authenticated;
revoke all on function app_month(uuid, int, int, uuid)           from public, anon, authenticated;
revoke all on function app_meds(uuid, uuid)                      from public, anon, authenticated;
revoke all on function app_med_add(uuid, text, time[], uuid)     from public, anon, authenticated;
grant execute on function app_month(uuid, int, int, uuid)        to anon, authenticated;
grant execute on function app_meds(uuid, uuid)                   to anon, authenticated;
grant execute on function app_med_add(uuid, text, time[], uuid)  to anon, authenticated;

drop function if exists app_update_parent(uuid, text, text, text, time, text);

create or replace function app_update_parent(
  p_app_token uuid,
  p_name text,
  p_city text,
  p_timezone text,
  p_checkin_time time,
  p_phone text,
  p_parent_id uuid default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return false; end if;

  update parents
     set display_name = coalesce(nullif(trim(p_name), ''), display_name),
         city         = nullif(trim(p_city), ''),
         timezone     = coalesce(nullif(trim(p_timezone), ''), timezone),
         checkin_time = coalesce(p_checkin_time, checkin_time),
         phone        = nullif(trim(p_phone), '')
   where id = v_parent.id;
  return true;
end $$;

revoke all on function app_update_parent(uuid, text, text, text, time, text, uuid)
  from public, anon, authenticated;
grant execute on function app_update_parent(uuid, text, text, text, time, text, uuid)
  to anon, authenticated;
