create table if not exists postcards (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references families(id) on delete cascade,
  parent_id   uuid not null references parents(id) on delete cascade,
  author_name text not null,
  body        text not null,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);

create index if not exists postcards_pending on postcards (parent_id) where sent_at is null;

alter table postcards enable row level security;

create policy postcards_read on postcards for select
  using (is_family_member(family_id));

create or replace function app_send_postcard(p_app_token uuid, p_parent_id uuid, p_body text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_author text;
  v_body   text;
begin
  v_body := trim(coalesce(p_body, ''));
  if v_body = '' or length(v_body) > 500 then
    return false;
  end if;

  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  if not exists (select 1 from parents
                 where id = p_parent_id and family_id = v_family.id
                   and telegram_user_id is not null) then
    return false;
  end if;

  select display_name into v_author
  from family_members
  where family_id = v_family.id and user_id = auth.uid()
  limit 1;

  if v_author is null then
    select display_name into v_author
    from family_members
    where family_id = v_family.id and role = 'owner'
    limit 1;
  end if;

  insert into postcards (family_id, parent_id, author_name, body)
  values (v_family.id, p_parent_id, coalesce(v_author, ''), v_body);
  return true;
end $$;

create or replace function postcards_due()
returns table (
  postcard_id      uuid,
  telegram_user_id bigint,
  author_name      text,
  body             text
)
language sql stable as $$
  select c.id, p.telegram_user_id, c.author_name, c.body
  from postcards c
  join parents p on p.id = c.parent_id
  where c.sent_at is null
    and p.telegram_user_id is not null
    and p.bot_state = 'active'
    and (now() at time zone p.timezone)::time >= time '08:00'
    and (now() at time zone p.timezone)::time <  time '23:00'
  order by c.created_at
  limit 20;
$$;

create or replace function mark_postcard_sent(p_id uuid)
returns void
language sql as $$
  update postcards set sent_at = now() where id = p_id and sent_at is null;
$$;

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
begin
  v_parent_json := jsonb_build_object(
    'id',           v_parent.id,
    'kind',         v_parent.kind,
    'display_name', v_parent.display_name,
    'city',         v_parent.city,
    'phone',        v_parent.phone,
    'timezone',     v_parent.timezone,
    'checkin_time', to_char(v_parent.checkin_time, 'HH24:MI'),
    'window_min',   v_parent.window_min
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

  return jsonb_build_object(
    'parent', v_parent_json,
    'status', v_status,
    'streak', v_streak,
    'meds',   jsonb_build_object('taken', v_meds_taken, 'total', v_meds_total)
  );
end $$;

create or replace function app_snapshot(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_cards  jsonb := '[]'::jsonb;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  for v_parent in
    select * from parents where family_id = v_family.id order by created_at
  loop
    v_cards := v_cards || jsonb_build_array(app_parent_card(v_parent));
  end loop;

  if jsonb_array_length(v_cards) = 0 then return null; end if;

  return (v_cards -> 0) || jsonb_build_object('parents', v_cards);
end $$;

create or replace function app_add_parent(
  p_app_token    uuid,
  p_display_name text,
  p_kind         text,
  p_city         text,
  p_timezone     text,
  p_checkin_time time
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_code   text;
begin
  if p_kind not in ('mom', 'dad', 'custom') then
    return null;
  end if;

  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  if (select count(*) from parents where family_id = v_family.id) >= 6 then
    return null;
  end if;

  insert into parents (family_id, kind, display_name, city, timezone, checkin_time)
  values (v_family.id, p_kind,
          coalesce(nullif(trim(p_display_name), ''), 'Родитель'),
          nullif(trim(p_city), ''), p_timezone, p_checkin_time)
  returning * into v_parent;

  v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  insert into invites (code, family_id, parent_id, created_by)
  values (v_code, v_family.id, v_parent.id, v_family.owner_id);

  return jsonb_build_object('parent_id', v_parent.id, 'invite_code', v_code);
end $$;

revoke all on function app_parent_card(parents)                          from public, anon, authenticated;
revoke all on function app_send_postcard(uuid, uuid, text)               from public, anon, authenticated;
revoke all on function postcards_due()                                   from public, anon, authenticated;
revoke all on function mark_postcard_sent(uuid)                          from public, anon, authenticated;
revoke all on function app_add_parent(uuid, text, text, text, text, time) from public, anon, authenticated;
grant execute on function app_send_postcard(uuid, uuid, text)               to anon, authenticated;
grant execute on function app_add_parent(uuid, text, text, text, text, time) to anon, authenticated;
