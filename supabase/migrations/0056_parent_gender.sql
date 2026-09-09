alter table parents add column if not exists gender text not null default 'f'
  check (gender in ('f', 'm'));
update parents set gender = 'm' where kind = 'dad';

drop function if exists app_add_parent(uuid, text, text, text, text, time, text);
create or replace function app_add_parent(
  p_app_token    uuid,
  p_display_name text,
  p_kind         text,
  p_city         text,
  p_timezone     text,
  p_checkin_time time,
  p_lang         text default 'ru',
  p_gender       text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_code   text;
  v_gender text;
begin
  if p_kind not in ('mom', 'dad', 'custom') then
    return null;
  end if;
  if p_lang not in ('ru', 'en') then
    p_lang := 'ru';
  end if;
  v_gender := case when p_gender in ('f', 'm') then p_gender when p_kind = 'dad' then 'm' else 'f' end;

  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  if (select count(*) from parents where family_id = v_family.id) >= 6 then
    return null;
  end if;
  if (select count(*) from parents where family_id = v_family.id) >= 1
     and family_entitlement(p_app_token) is null then
    return null;
  end if;

  insert into parents (family_id, kind, gender, display_name, city, timezone, checkin_time, lang)
  values (v_family.id, p_kind, v_gender,
          coalesce(nullif(trim(p_display_name), ''), 'Родитель'),
          nullif(trim(p_city), ''), p_timezone, p_checkin_time, p_lang)
  returning * into v_parent;

  v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  insert into invites (code, family_id, parent_id, created_by)
  values (v_code, v_family.id, v_parent.id, v_family.owner_id);

  return jsonb_build_object('parent_id', v_parent.id, 'invite_code', v_code);
end $$;


revoke all on function app_add_parent(uuid, text, text, text, text, time, text, text)
  from public, anon, authenticated;
grant execute on function app_add_parent(uuid, text, text, text, text, time, text, text)
  to anon, authenticated;

drop function if exists app_update_parent(uuid, text, text, text, time, text, uuid, text);
create or replace function app_update_parent(
  p_app_token uuid,
  p_name text,
  p_city text,
  p_timezone text,
  p_checkin_time time,
  p_phone text,
  p_parent_id uuid default null,
  p_lang text default null,
  p_gender text default null
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
         phone        = nullif(trim(p_phone), ''),

         lang         = coalesce(case when p_lang in ('ru', 'en') then p_lang end, lang),
         gender       = coalesce(case when p_gender in ('f', 'm') then p_gender end, gender)
   where id = v_parent.id;
  return true;
end $$;


revoke all on function app_update_parent(uuid, text, text, text, time, text, uuid, text, text)
  from public, anon, authenticated;
grant execute on function app_update_parent(uuid, text, text, text, time, text, uuid, text, text)
  to anon, authenticated;

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

