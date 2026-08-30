create or replace function create_family_with_parent(
  p_parent_name text,
  p_timezone text,
  p_checkin_time time,
  p_child_name text,
  p_child_gender text,
  p_child_timezone text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_code   text;
begin
  if auth.uid() is null then
    return null;
  end if;
  if p_child_gender not in ('son', 'daughter') then
    return null;
  end if;

  insert into families (owner_id) values (auth.uid()) returning * into v_family;

  insert into family_members (family_id, user_id, role, child_gender, display_name, timezone)
  values (v_family.id, auth.uid(), 'owner', p_child_gender,
          coalesce(nullif(trim(p_child_name), ''), 'Ваш ребёнок'), p_child_timezone);

  insert into parents (family_id, kind, display_name, timezone, checkin_time)
  values (v_family.id, 'mom',
          coalesce(nullif(trim(p_parent_name), ''), 'Мама'), p_timezone, p_checkin_time)
  returning * into v_parent;

  v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  insert into invites (code, family_id, parent_id, created_by)
  values (v_code, v_family.id, v_parent.id, auth.uid());

  return jsonb_build_object(
    'family_id',   v_family.id,
    'app_token',   v_family.app_token,
    'parent_id',   v_parent.id,
    'invite_code', v_code
  );
end $$;

revoke all on function create_family_with_parent(text, text, time, text, text, text)
  from public, anon;
grant execute on function create_family_with_parent(text, text, time, text, text, text)
  to authenticated;

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

revoke all on function app_snapshot(uuid) from public, anon, authenticated;
grant execute on function app_snapshot(uuid) to anon, authenticated;

create or replace function bind_invite(p_code text, p_telegram_user_id bigint)
returns jsonb
language plpgsql as $$
declare
  v_invite invites%rowtype;
  v_child  family_members%rowtype;
begin
  update invites
     set bound_at = now()
   where code = p_code
     and bound_at is null
     and expires_at > now()
  returning * into v_invite;

  if not found then
    return null;
  end if;

  update parents
     set telegram_user_id = p_telegram_user_id,
         bot_state = 'onboarding'
   where id = v_invite.parent_id;

  select * into v_child from family_members
   where family_id = v_invite.family_id and user_id = v_invite.created_by;

  return jsonb_build_object(
    'parent_id',    v_invite.parent_id,
    'family_id',    v_invite.family_id,
    'child_name',   v_child.display_name,
    'child_gender', v_child.child_gender
  );
end $$;

revoke all on function bind_invite(text, bigint) from public, anon, authenticated;
