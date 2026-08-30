alter table med_events add column last_reminded_at timestamptz;
alter table med_events add column remind_count int not null default 0;

create or replace function app_meds(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  select p.* into v_parent
  from parents p
  join families f on f.id = p.family_id
  where f.app_token = p_app_token
  order by p.created_at
  limit 1;
  if not found then return null; end if;

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

create or replace function app_med_add(p_app_token uuid, p_title text, p_times time[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_med meds%rowtype;
begin
  select p.* into v_parent
  from parents p
  join families f on f.id = p.family_id
  where f.app_token = p_app_token
  order by p.created_at
  limit 1;
  if not found then return null; end if;
  if nullif(trim(p_title), '') is null or cardinality(p_times) = 0 then
    return null;
  end if;

  insert into meds (parent_id, title, human_text, times)
  values (v_parent.id, trim(p_title), trim(p_title), p_times)
  returning * into v_med;

  return jsonb_build_object('id', v_med.id);
end $$;

create or replace function app_med_delete(p_app_token uuid, p_med_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_deleted boolean;
begin
  delete from meds m
  using parents p, families f
  where m.id = p_med_id
    and m.parent_id = p.id
    and p.family_id = f.id
    and f.app_token = p_app_token;
  v_deleted := found;
  return v_deleted;
end $$;

revoke all on function app_meds(uuid) from public, anon, authenticated;
revoke all on function app_med_add(uuid, text, time[]) from public, anon, authenticated;
revoke all on function app_med_delete(uuid, uuid) from public, anon, authenticated;
grant execute on function app_meds(uuid) to anon, authenticated;
grant execute on function app_med_add(uuid, text, time[]) to anon, authenticated;
grant execute on function app_med_delete(uuid, uuid) to anon, authenticated;

create or replace function meds_due()
returns table (
  telegram_user_id bigint,
  family_id uuid,
  med_id uuid,
  med_title text,
  slot time,
  address_form text,
  display_name text,
  is_repeat boolean,
  local_date date
)
language sql stable as $$

  select p.telegram_user_id, p.family_id, m.id, m.title, s.slot,
         p.address_form, p.display_name, false,
         (now() at time zone p.timezone)::date
  from meds m
  join parents p on p.id = m.parent_id
  cross join lateral unnest(m.times) as s(slot)
  where m.active
    and p.bot_state = 'active'
    and p.telegram_user_id is not null
    and extract(isodow from (now() at time zone p.timezone))::int = any(m.days)
    and (now() at time zone p.timezone)::time >= s.slot
    and (now() at time zone p.timezone)::time < s.slot + interval '10 minutes'
    and not exists (
      select 1 from med_events e
      where e.med_id = m.id
        and e.local_date = (now() at time zone p.timezone)::date
        and e.slot = s.slot
    )
  union all

  select p.telegram_user_id, p.family_id, m.id, m.title, e.slot,
         p.address_form, p.display_name, true,
         e.local_date
  from med_events e
  join meds m on m.id = e.med_id
  join parents p on p.id = m.parent_id
  where e.status = 'postponed'
    and e.remind_count < 3
    and e.last_reminded_at <= now() - interval '30 minutes'
    and e.local_date = (now() at time zone p.timezone)::date
    and p.bot_state = 'active'
    and p.telegram_user_id is not null;
$$;

create or replace function med_remind_started(p_med_id uuid, p_local_date date, p_slot time)
returns void
language sql as $$
  insert into med_events (med_id, local_date, slot, status, last_reminded_at, remind_count)
  values (p_med_id, p_local_date, p_slot, 'no_answer', now(), 1)
  on conflict (med_id, local_date, slot) do update
    set last_reminded_at = now(),
        remind_count = med_events.remind_count + 1,
        status = 'no_answer';
$$;

create or replace function med_mark(
  p_telegram_user_id bigint,
  p_med_id uuid,
  p_slot time,
  p_status text
) returns boolean
language plpgsql as $$
declare
  v_updated boolean;
begin
  if p_status not in ('taken', 'postponed') then
    return false;
  end if;
  update med_events e
     set status = p_status,
         last_reminded_at = now()
    from meds m, parents p
   where e.med_id = p_med_id
     and m.id = e.med_id
     and p.id = m.parent_id
     and p.telegram_user_id = p_telegram_user_id
     and e.local_date = (now() at time zone p.timezone)::date
     and e.slot = p_slot;
  v_updated := found;
  return v_updated;
end $$;

revoke all on function meds_due() from public, anon, authenticated;
revoke all on function med_remind_started(uuid, date, time) from public, anon, authenticated;
revoke all on function med_mark(bigint, uuid, time, text) from public, anon, authenticated;

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
