alter table parents add column phone text;

create or replace function app_update_parent(
  p_app_token uuid,
  p_name text,
  p_city text,
  p_timezone text,
  p_checkin_time time,
  p_phone text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_updated boolean;
begin
  if nullif(trim(p_name), '') is null then
    return false;
  end if;
  update parents p
     set display_name = trim(p_name),
         city = nullif(trim(p_city), ''),
         timezone = p_timezone,
         checkin_time = p_checkin_time,
         phone = nullif(trim(p_phone), '')
    from families f
   where p.family_id = f.id
     and f.app_token = p_app_token
     and p.id = (
       select id from parents
       where family_id = f.id
       order by created_at
       limit 1
     );
  v_updated := found;
  return v_updated;
end $$;

revoke all on function app_update_parent(uuid, text, text, text, time, text)
  from public, anon, authenticated;
grant execute on function app_update_parent(uuid, text, text, text, time, text)
  to anon, authenticated;

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
  v_invite   text;
  v_meds_taken int := 0;
  v_meds_total int := 0;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  select * into v_parent
  from parents
  where family_id = v_family.id
  order by created_at
  limit 1;
  if not found then return null; end if;

  if v_parent.telegram_user_id is null then
    select code into v_invite
    from invites
    where parent_id = v_parent.id and bound_at is null and expires_at > now()
    order by expires_at desc
    limit 1;

    return jsonb_build_object(
      'parent', jsonb_build_object(
        'id',           v_parent.id,
        'kind',         v_parent.kind,
        'display_name', v_parent.display_name,
        'city',         v_parent.city,
        'phone',        v_parent.phone,
        'timezone',     v_parent.timezone,
        'checkin_time', to_char(v_parent.checkin_time, 'HH24:MI'),
        'window_min',   v_parent.window_min
      ),
      'status', jsonb_build_object('state', 'waiting_parent'),
      'streak', 0,
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
        'city',         v_parent.city,
        'phone',        v_parent.phone,
      'timezone',     v_parent.timezone,
      'checkin_time', to_char(v_parent.checkin_time, 'HH24:MI'),
      'window_min',   v_parent.window_min
    ),
    'status', v_status,
    'streak', v_streak,
    'meds', jsonb_build_object('taken', v_meds_taken, 'total', v_meds_total)
  );
end;
$$;

revoke all on function app_snapshot(uuid) from public, anon, authenticated;
grant execute on function app_snapshot(uuid) to anon, authenticated;
