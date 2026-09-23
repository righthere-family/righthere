create table if not exists family_reaches (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references families(id) on delete cascade,
  parent_id   uuid not null references parents(id) on delete cascade,
  member_id   uuid not null references auth.users(id) on delete cascade,
  author_name text not null default '',
  local_date  date not null,
  sent_at     timestamptz,
  created_at  timestamptz not null default now(),
  unique (parent_id, local_date)
);

create index if not exists family_reaches_pending on family_reaches (created_at) where sent_at is null;

alter table family_reaches enable row level security;

create or replace function app_set_my_name(p_app_token uuid, p_name text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_member family_members%rowtype;
  v_name   text;
begin
  v_name := left(trim(coalesce(p_name, '')), 40);
  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  v_member := family_join_caller(v_family.id);
  if v_member.user_id is null then
    perform log_refusal(p_app_token, 'name', 'no signed-in session');
    return false;
  end if;

  update family_members set display_name = v_name
   where family_id = v_family.id and user_id = auth.uid();
  return true;
end $$;

revoke all on function app_set_my_name(uuid, text) from public, anon, authenticated;
grant execute on function app_set_my_name(uuid, text) to anon, authenticated;

create or replace function app_reached(p_app_token uuid, p_parent_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_member family_members%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  select * into v_parent from parents where id = p_parent_id and family_id = v_family.id;
  if not found then
    perform log_refusal(p_app_token, 'reached', 'parent not in this family', p_parent_id);
    return false;
  end if;

  v_member := family_join_caller(v_family.id);
  if v_member.user_id is null then
    perform log_refusal(p_app_token, 'reached', 'no signed-in session', p_parent_id);
    return false;
  end if;

  insert into family_reaches (family_id, parent_id, member_id, author_name, local_date)
  values (v_family.id, v_parent.id, v_member.user_id,
          coalesce(v_member.display_name, ''), parent_local_date(v_parent.id))
  on conflict (parent_id, local_date) do nothing;

  update escalations
     set state = 'resolved_by_child', resolved_at = now(), resolved_by = v_member.user_id
   where parent_id = v_parent.id
     and local_date = parent_local_date(v_parent.id)
     and state in ('reping_sent', 'children_notified');

  perform ring_family(v_family.id, 'detail');
  return true;
end $$;

revoke all on function app_reached(uuid, uuid) from public, anon, authenticated;
grant execute on function app_reached(uuid, uuid) to anon, authenticated;

create or replace function reaches_due()
returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'reach_id',    r.id,
           'family_id',   r.family_id,
           'parent_id',   r.parent_id,
           'parent_name', coalesce(p.address_form, p.display_name),
           'author',      r.author_name,
           'member_id',   r.member_id,
           'gender',      coalesce(m.child_gender, 'son')
         ) order by r.created_at), '[]'::jsonb)
  from family_reaches r
  join parents p on p.id = r.parent_id
  left join family_members m on m.family_id = r.family_id and m.user_id = r.member_id
  where r.sent_at is null
    and r.created_at > now() - interval '12 hours';
$$;

revoke all on function reaches_due() from public, anon, authenticated;

create or replace function mark_reach_sent(p_id uuid)
returns void
language sql as $$
  update family_reaches set sent_at = now() where id = p_id;
$$;

revoke all on function mark_reach_sent(uuid) from public, anon, authenticated;

create or replace function app_parent_card(v_parent parents)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today   date;
  v_checkin checkins%rowtype;
  v_esc     escalations%rowtype;
  v_run     daily_runs%rowtype;
  v_reach   family_reaches%rowtype;
  v_streak  int := 0;
  v_status  jsonb;
  v_invite  text;
  v_meds_taken int := 0;
  v_meds_total int := 0;
  v_parent_json jsonb;
  v_evening jsonb;
  v_reached jsonb;
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
    'lang',         v_parent.lang,
    'bot_state',    v_parent.bot_state,
    'paused_until', to_char(v_parent.paused_until, 'YYYY-MM-DD')
  );

  if v_parent.telegram_user_id is null and v_parent.bot_state <> 'archived' then
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
  select * into v_reach   from family_reaches where parent_id = v_parent.id and local_date = v_today;

  v_streak := parent_streak(v_parent.id, case when v_checkin.id is null then v_today - 1 else v_today end);

  if v_parent.bot_state <> 'archived' then
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
  end if;

  if v_reach.id is not null then
    v_reached := jsonb_build_object(
      'name', v_reach.author_name,
      'at',   iso_utc(v_reach.created_at),
      'mine', v_reach.member_id = auth.uid()
    );
  end if;

  if v_parent.bot_state = 'archived' then
    v_status := jsonb_build_object('state', 'archived');
  elsif v_checkin.id is not null and v_checkin.status in ('ok', 'accidental_ok') then
    v_status := jsonb_build_object('state', 'ok', 'at', iso_utc(v_checkin.created_at));
  elsif v_checkin.id is not null then
    v_status := jsonb_build_object(
      'state', 'not_ok',
      'at',    iso_utc(v_checkin.created_at),
      'kind',  v_checkin.not_ok_kind,
      'quote', v_checkin.free_text
    );
  elsif v_parent.bot_state = 'paused' and v_parent.paused_until is not null
     and v_parent.paused_until >= v_today then
    v_status := jsonb_build_object('state', 'paused', 'until', to_char(v_parent.paused_until, 'YYYY-MM-DD'));
  elsif v_parent.bot_state = 'blocked' then
    v_status := jsonb_build_object('state', 'blocked');
  elsif v_esc.id is not null and v_esc.state in ('reping_sent', 'children_notified', 'resolved_by_child') then
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

  return jsonb_strip_nulls(jsonb_build_object(
    'parent',  v_parent_json,
    'status',  v_status,
    'streak',  v_streak,
    'meds',    jsonb_build_object('taken', v_meds_taken, 'total', v_meds_total),
    'evening', v_evening,
    'reached', v_reached
  )) || jsonb_build_object(
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

create or replace function app_snapshot(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_cards  jsonb := '[]'::jsonb;
  v_first  parents%rowtype;
  v_upcoming jsonb;
  v_me     text;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  for v_parent in
    select * from parents where family_id = v_family.id
    order by (bot_state = 'archived'), created_at
  loop
    if v_first.id is null then v_first := v_parent; end if;
    v_cards := v_cards || jsonb_build_array(app_parent_card(v_parent));
  end loop;

  if jsonb_array_length(v_cards) = 0 then return null; end if;

  v_upcoming := app_upcoming_date(
    v_family.id,
    (now() at time zone v_first.timezone)::date
  );

  select display_name into v_me from family_members
  where family_id = v_family.id and user_id = auth.uid();

  return (v_cards -> 0)
    || jsonb_build_object('parents', v_cards)
    || jsonb_build_object('me', jsonb_build_object('name', coalesce(v_me, ''), 'known', v_me is not null))
    || coalesce(jsonb_build_object('upcoming_date', v_upcoming), '{}'::jsonb);
end $$;
