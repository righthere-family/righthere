alter table parents drop constraint parents_bot_state_check;
alter table parents add constraint parents_bot_state_check
  check (bot_state in ('invited', 'onboarding', 'active', 'paused', 'stopped', 'blocked', 'demo', 'archived'));

alter table parents add column if not exists paused_by text
  check (paused_by in ('parent', 'child'));
alter table parents add column if not exists archived_at timestamptz;
alter table parents add column if not exists pending_notice text
  check (pending_notice in ('paused', 'resumed'));

update parents set paused_by = 'parent' where bot_state = 'paused' and paused_by is null;

create table if not exists parent_pauses (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid not null references parents(id) on delete cascade,
  starts_on  date not null,
  ends_on    date not null,
  set_by     text not null check (set_by in ('parent', 'child')),
  created_at timestamptz not null default now()
);

create index if not exists parent_pauses_parent on parent_pauses (parent_id, ends_on desc);

alter table parent_pauses enable row level security;

insert into parent_pauses (parent_id, starts_on, ends_on, set_by)
select p.id, (now() at time zone p.timezone)::date, p.paused_until, 'parent'
from parents p
where p.bot_state = 'paused'
  and p.paused_until is not null
  and p.paused_until >= (now() at time zone p.timezone)::date;

create or replace function parent_pause_set(p_parent_id uuid, p_until date, p_by text)
returns void
language plpgsql as $$
declare
  v_today date;
  v_open  uuid;
begin
  v_today := parent_local_date(p_parent_id);
  select id into v_open from parent_pauses
   where parent_id = p_parent_id and starts_on <= v_today and ends_on >= v_today
   order by ends_on desc
   limit 1;
  if v_open is not null then
    update parent_pauses set ends_on = p_until where id = v_open;
  else
    insert into parent_pauses (parent_id, starts_on, ends_on, set_by)
    values (p_parent_id, v_today, p_until, p_by);
  end if;
  update parents
     set paused_by    = case when bot_state = 'paused' then coalesce(paused_by, p_by) else p_by end,
         bot_state    = 'paused',
         paused_until = p_until
   where id = p_parent_id;
end $$;

create or replace function parent_pause_clear(p_parent_id uuid)
returns void
language plpgsql as $$
declare
  v_today date;
begin
  v_today := parent_local_date(p_parent_id);
  update parent_pauses set ends_on = v_today - 1
   where parent_id = p_parent_id and ends_on >= v_today;
  delete from parent_pauses
   where parent_id = p_parent_id and ends_on < starts_on;
  update parents
     set bot_state = 'active', paused_until = null, paused_by = null
   where id = p_parent_id and bot_state = 'paused';
end $$;

revoke all on function parent_pause_set(uuid, date, text) from public, anon, authenticated;
revoke all on function parent_pause_clear(uuid) from public, anon, authenticated;

create or replace function parent_streak(p_parent_id uuid, p_anchor date)
returns int
language sql stable as $$
  with days as (
    select (p_anchor - g)::date as d, g
    from generate_series(0, 730) as g
  ),
  marked as (
    select d.g,
           (select c.status from checkins c
             where c.parent_id = p_parent_id and c.local_date = d.d) as status,
           exists (select 1 from daily_runs r
                    where r.parent_id = p_parent_id and r.local_date = d.d
                      and r.morning_sent_at is not null and r.delivery_ok) as asked
    from days d
  ),
  broken as (
    select min(g) as at from marked
    where status = 'not_ok' or (status is null and asked)
  )
  select count(*)::int
  from marked m, broken b
  where m.status in ('ok', 'accidental_ok')
    and m.g < coalesce(b.at, 731);
$$;

revoke all on function parent_streak(uuid, date) from public, anon, authenticated;

create or replace function record_checkin(
  p_telegram_user_id bigint,
  p_status text,
  p_source text
) returns jsonb
language plpgsql as $$
declare
  v_parent    parents%rowtype;
  v_today     date;
  v_existing  checkins%rowtype;
  v_escalated boolean := false;
  v_resumed   boolean := false;
  v_result    text := 'ok';
  v_streak    int := 0;
  v_milestone int;
  v_total     int := 0;
begin
  select * into v_parent from parents where telegram_user_id = p_telegram_user_id;
  if not found then
    return jsonb_build_object('result', 'unknown_parent');
  end if;
  if v_parent.bot_state = 'archived' then
    return jsonb_build_object('result', 'archived', 'parent_id', v_parent.id, 'family_id', v_parent.family_id);
  end if;

  v_today := (now() at time zone v_parent.timezone)::date;

  select * into v_existing from checkins
    where parent_id = v_parent.id and local_date = v_today;

  if found then
    if v_existing.status = 'not_ok' and p_status = 'ok' then
      update checkins
         set status = 'ok', source = p_source, not_ok_kind = null, free_text = null
       where id = v_existing.id;
      v_result := 'upgraded';
    elsif v_existing.status in ('ok', 'accidental_ok') and p_status = 'not_ok' then
      update checkins
         set status = 'not_ok', source = p_source, not_ok_kind = null, free_text = null
       where id = v_existing.id;
      v_result := 'worsened';
    else
      return jsonb_build_object('result', 'duplicate');
    end if;
  else
    begin
      insert into checkins (parent_id, local_date, status, source)
      values (v_parent.id, v_today, p_status, p_source);
    exception when unique_violation then
      return jsonb_build_object('result', 'duplicate');
    end;
  end if;

  update escalations
     set state = 'resolved_by_parent', resolved_at = now()
   where parent_id = v_parent.id
     and local_date = v_today
     and state in ('reping_sent', 'children_notified');
  v_escalated := found;

  if v_parent.bot_state = 'paused' and v_parent.paused_by = 'parent' then
    perform parent_pause_clear(v_parent.id);
    v_resumed := true;
  end if;

  v_streak := parent_streak(v_parent.id, v_today);

  select count(*) into v_total from checkins where parent_id = v_parent.id;

  if p_status = 'ok' and v_streak in (7, 30, 100, 365) then
    v_milestone := v_streak;
  end if;

  return jsonb_build_object(
    'result', v_result,
    'was_escalated', v_escalated,
    'resumed', v_resumed,
    'streak', v_streak,
    'milestone', v_milestone,
    'first', v_result = 'ok' and v_total = 1,
    'silent_before', parent_silent_days(v_parent.id, v_today - 1),
    'parent_id', v_parent.id,
    'family_id', v_parent.family_id
  );
end $$;

revoke all on function record_checkin(bigint, text, text) from public, anon, authenticated;

create or replace function app_parent_card(v_parent parents)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today   date;
  v_checkin checkins%rowtype;
  v_esc     escalations%rowtype;
  v_run     daily_runs%rowtype;
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
  elsif v_esc.id is not null and v_esc.state in ('reping_sent', 'children_notified') then
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

create or replace function app_snapshot(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_cards  jsonb := '[]'::jsonb;
  v_first  parents%rowtype;
  v_upcoming jsonb;
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

  return (v_cards -> 0)
    || jsonb_build_object('parents', v_cards)
    || coalesce(jsonb_build_object('upcoming_date', v_upcoming), '{}'::jsonb);
end $$;

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
  v_archived date;
  v_days   jsonb;
begin
  if p_month not between 1 and 12 or p_year not between 2020 and 2100 then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;

  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;

  v_today := (now() at time zone v_parent.timezone)::date;
  if make_date(p_year, p_month, 1) < date_trunc('month', v_today)::date
     and family_entitlement(p_app_token) is null then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;
  v_start := (v_parent.created_at at time zone v_parent.timezone)::date;
  v_archived := (v_parent.archived_at at time zone v_parent.timezone)::date;
  v_first := make_date(p_year, p_month, 1);

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'day',   extract(day from d)::int,
    'mark',  case
               when d > v_today or d < v_start then 'upcoming'
               when c.status in ('ok', 'accidental_ok') then 'ok'
               when c.status = 'not_ok' then 'not_ok'
               when v_archived is not null and d >= v_archived then 'off'
               when exists (select 1 from parent_pauses x
                            where x.parent_id = v_parent.id
                              and d::date between x.starts_on and x.ends_on) then 'paused'
               when d = v_today then 'today'
               when r.morning_sent_at is not null and r.delivery_ok then 'missed'
               else 'off'
             end,
    'time',  case when c.status in ('ok', 'accidental_ok')
                  then to_char(c.created_at at time zone v_parent.timezone, 'HH24:MI') end,
    'quote', case when c.status = 'not_ok' then c.free_text end
  )) order by d), '[]'::jsonb)
  into v_days
  from generate_series(v_first, (v_first + interval '1 month' - interval '1 day')::date, '1 day') as d
  left join checkins c on c.parent_id = v_parent.id and c.local_date = d::date
  left join daily_runs r on r.parent_id = v_parent.id and r.local_date = d::date;

  return jsonb_build_object(
    'today', case when date_trunc('month', v_today::timestamp)::date = v_first
                  then extract(day from v_today)::int end,
    'days',  v_days
  );
end;
$$;

create or replace function app_set_pause(p_app_token uuid, p_parent_id uuid, p_until date default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today  date;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null or v_parent.bot_state not in ('active', 'paused') then
    return false;
  end if;
  v_today := (now() at time zone v_parent.timezone)::date;

  if p_until is null then
    if v_parent.bot_state = 'paused' then
      perform parent_pause_clear(v_parent.id);
      update parents
         set pending_notice = case when pending_notice = 'paused' then null else 'resumed' end
       where id = v_parent.id;
    end if;
  else
    if p_until < v_today or p_until > v_today + 366 then
      return false;
    end if;
    perform parent_pause_set(v_parent.id, p_until, 'child');
    update parents
       set pending_notice = case when pending_notice = 'resumed' then null else 'paused' end
     where id = v_parent.id;
  end if;

  perform ring_family(v_parent.family_id, 'pause');
  return true;
end $$;

revoke all on function app_set_pause(uuid, uuid, date) from public, anon, authenticated;
grant execute on function app_set_pause(uuid, uuid, date) to anon, authenticated;

create or replace function app_archive_parent(p_app_token uuid, p_parent_id uuid, p_archived boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null or v_parent.bot_state = 'demo' then
    return false;
  end if;

  if p_archived then
    if v_parent.bot_state = 'archived' then return true; end if;
    if v_parent.bot_state = 'paused' then
      perform parent_pause_clear(v_parent.id);
    end if;
    update parents
       set bot_state      = 'archived',
           archived_at    = now(),
           paused_until   = null,
           paused_by      = null,
           pending_notice = null
     where id = v_parent.id;
  else
    if v_parent.bot_state <> 'archived' then return true; end if;
    update parents
       set bot_state   = case when telegram_user_id is null then 'invited' else 'active' end,
           archived_at = null
     where id = v_parent.id;
  end if;

  perform ring_family(v_parent.family_id, 'pause');
  return true;
end $$;

revoke all on function app_archive_parent(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function app_archive_parent(uuid, uuid, boolean) to anon, authenticated;

create or replace function cron_housekeeping()
returns void
language sql as $$
  update parents
     set bot_state = 'active', paused_until = null, paused_by = null
   where bot_state = 'paused'
     and paused_until is not null
     and paused_until < (now() at time zone timezone)::date;

  delete from bot_events where at < now() - interval '30 days';
$$;

create or replace function pause_notices_due()
returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'parent_id',        p.id,
    'telegram_user_id', p.telegram_user_id,
    'lang',             p.lang,
    'kind',             p.pending_notice,
    'until',            to_char(p.paused_until, 'YYYY-MM-DD')
  )), '[]'::jsonb)
  from parents p
  where p.pending_notice is not null
    and p.telegram_user_id is not null
    and p.bot_state in ('active', 'paused');
$$;

revoke all on function pause_notices_due() from public, anon, authenticated;

insert into daily_runs (parent_id, local_date, morning_sent_at, delivery_ok)
select p.id, d::date,
       ((d::date + p.checkin_time) at time zone p.timezone),
       true
from parents p
cross join generate_series((now() at time zone p.timezone)::date - 60,
                           (now() at time zone p.timezone)::date - 1, '1 day') as d
where p.bot_state = 'demo'
on conflict do nothing;

create or replace function demo_tick()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_p      parents%rowtype;
  v_local  timestamp;
  v_date   date;
  v_doy    int;
  v_jitter int;
  v_status text;
  v_name   text;
  v_events jsonb := '[]'::jsonb;
  v_msgs   text[] := array[
    'Baked your favourite apple pie, wish you were here for a slice.',
    'The neighbours dropped by for tea. All good here.',
    'Doctor''s visit went fine, pressure is normal.',
    'Watching the old photos again. Call when you have a minute, no rush.',
    'Bought new curtains for the kitchen, the yellow ones.',
    'Everything is fine. Hugs to all of you.'
  ];
begin
  for v_p in select * from parents where bot_state = 'demo' loop
    v_local  := now() at time zone v_p.timezone;
    v_date   := v_local::date;
    v_doy    := extract(doy from v_date)::int;
    v_jitter := 3 + (v_doy * 7) % 40;
    v_name   := coalesce(v_p.address_form, v_p.display_name);

    if v_local::time >= v_p.checkin_time then
      insert into daily_runs (parent_id, local_date, morning_sent_at, delivery_ok)
      values (v_p.id, v_date, (v_date + v_p.checkin_time) at time zone v_p.timezone, true)
      on conflict do nothing;
    end if;

    if v_local::time >= v_p.checkin_time + make_interval(mins => v_jitter)
       and not exists (select 1 from checkins where parent_id = v_p.id and local_date = v_date) then
      v_status := case when v_doy % 9 = 0 then 'not_ok' else 'ok' end;
      insert into checkins (parent_id, local_date, status, source, not_ok_kind, free_text)
      values (v_p.id, v_date, v_status, 'button',
              case when v_status = 'not_ok' then 'just_day' end,
              case when v_status = 'not_ok' then 'Just one of those days.' end);
      v_events := v_events || jsonb_build_object(
        'family_id', v_p.family_id, 'name', v_name, 'kind', 'checkin', 'status', v_status);
    end if;

    if v_doy % 3 = 0
       and v_local::time >= v_p.checkin_time + make_interval(mins => v_jitter + 65)
       and not exists (
         select 1 from parent_messages
         where parent_id = v_p.id
           and created_at >= (v_date::timestamp at time zone v_p.timezone)) then
      insert into parent_messages (family_id, parent_id, kind, body)
      values (v_p.family_id, v_p.id, 'text', v_msgs[1 + (v_doy / 3) % array_length(v_msgs, 1)]);
      v_events := v_events || jsonb_build_object(
        'family_id', v_p.family_id, 'name', v_name, 'kind', 'message');
    end if;
  end loop;
  return v_events;
end $$;

revoke all on function demo_tick() from public, anon, authenticated;
