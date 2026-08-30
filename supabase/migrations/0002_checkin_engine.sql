create table daily_runs (
  parent_id       uuid not null references parents(id) on delete cascade,
  local_date      date not null,
  morning_sent_at timestamptz,
  delivery_ok     boolean not null default true,
  reping_sent_at  timestamptz,
  primary key (parent_id, local_date)
);

alter table daily_runs enable row level security;

create policy daily_runs_read on daily_runs for select
  using (is_family_member((select family_id from parents p where p.id = parent_id)));

create or replace function parent_local_date(p_parent_id uuid)
returns date language sql stable as $$
  select (now() at time zone p.timezone)::date from parents p where p.id = p_parent_id;
$$;

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
  v_result    text := 'ok';
  v_streak    int := 0;
  v_milestone int;
begin
  select * into v_parent from parents where telegram_user_id = p_telegram_user_id;
  if not found then
    return jsonb_build_object('result', 'unknown_parent');
  end if;

  v_today := (now() at time zone v_parent.timezone)::date;

  select * into v_existing from checkins
    where parent_id = v_parent.id and local_date = v_today;

  if found then
    if v_existing.status = 'not_ok' and p_status = 'ok' then
      update checkins set status = 'ok', source = p_source where id = v_existing.id;
      v_result := 'upgraded';
    elsif v_existing.status in ('ok', 'accidental_ok') and p_status = 'not_ok' then
      update checkins set status = 'not_ok', source = p_source where id = v_existing.id;
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

  select count(*) into v_streak from (
    select local_date, row_number() over (order by local_date desc) as rn
    from checkins
    where parent_id = v_parent.id
      and status in ('ok', 'accidental_ok')
      and local_date <= v_today
  ) t
  where t.local_date = v_today - (t.rn - 1)::int;

  if p_status = 'ok' and v_streak in (7, 30, 100, 365) then
    v_milestone := v_streak;
  end if;

  return jsonb_build_object(
    'result', v_result,
    'was_escalated', v_escalated,
    'streak', v_streak,
    'milestone', v_milestone,
    'parent_id', v_parent.id,
    'family_id', v_parent.family_id
  );
end $$;

create or replace function set_not_ok_detail(
  p_telegram_user_id bigint,
  p_kind text,
  p_free_text text default null
) returns void
language sql as $$
  update checkins c
     set not_ok_kind = coalesce(p_kind, c.not_ok_kind),
         free_text = coalesce(p_free_text, c.free_text)
    from parents p
   where p.telegram_user_id = p_telegram_user_id
     and c.parent_id = p.id
     and c.local_date = (now() at time zone p.timezone)::date
     and c.status = 'not_ok';
$$;

create or replace function convert_to_accidental(p_telegram_user_id bigint)
returns boolean
language plpgsql as $$
declare v_updated boolean;
begin
  update checkins c
     set status = 'accidental_ok', not_ok_kind = null
    from parents p
   where p.telegram_user_id = p_telegram_user_id
     and c.parent_id = p.id
     and c.local_date = (now() at time zone p.timezone)::date
     and c.status = 'not_ok';
  v_updated := found;
  return v_updated;
end $$;

create or replace function parents_due_for_morning()
returns table (
  parent_id uuid, family_id uuid, telegram_user_id bigint,
  display_name text, address_form text, checkin_time time,
  window_min int, tz text, child_display_name text, local_date date
)
language sql stable as $$
  select p.id, p.family_id, p.telegram_user_id,
         p.display_name, p.address_form, p.checkin_time,
         p.window_min, p.timezone,
         coalesce(o.display_name, ''),
         (now() at time zone p.timezone)::date
  from parents p
  left join lateral (
    select fm.display_name from family_members fm
    where fm.family_id = p.family_id and fm.role = 'owner'
    limit 1
  ) o on true
  where p.bot_state = 'active'
    and p.telegram_user_id is not null
    and (p.paused_until is null or p.paused_until < (now() at time zone p.timezone)::date)
    and (now() at time zone p.timezone)::time >= p.checkin_time
    and (now() at time zone p.timezone)::time <  p.checkin_time + interval '45 minutes'
    and not exists (
      select 1 from checkins c
      where c.parent_id = p.id and c.local_date = (now() at time zone p.timezone)::date
    )
    and not exists (
      select 1 from daily_runs r
      where r.parent_id = p.id
        and r.local_date = (now() at time zone p.timezone)::date
        and r.morning_sent_at is not null
    );
$$;

create or replace function parents_due_for_reping()
returns table (
  parent_id uuid, family_id uuid, telegram_user_id bigint,
  display_name text, address_form text, checkin_time time,
  window_min int, tz text, child_display_name text, local_date date
)
language sql stable as $$
  select p.id, p.family_id, p.telegram_user_id,
         p.display_name, p.address_form, p.checkin_time,
         p.window_min, p.timezone,
         coalesce(o.display_name, ''),
         r.local_date
  from parents p
  join daily_runs r
    on r.parent_id = p.id
   and r.local_date = (now() at time zone p.timezone)::date
  left join lateral (
    select fm.display_name from family_members fm
    where fm.family_id = p.family_id and fm.role = 'owner'
    limit 1
  ) o on true
  where p.bot_state = 'active'
    and r.morning_sent_at is not null
    and r.delivery_ok
    and r.reping_sent_at is null
    and r.morning_sent_at <= now() - interval '90 minutes'
    and not exists (
      select 1 from checkins c
      where c.parent_id = p.id and c.local_date = r.local_date
    );
$$;

create or replace function parents_past_deadline()
returns table (
  parent_id uuid, family_id uuid, telegram_user_id bigint,
  display_name text, address_form text, checkin_time time,
  window_min int, tz text, child_display_name text, local_date date
)
language sql stable as $$
  select p.id, p.family_id, p.telegram_user_id,
         p.display_name, p.address_form, p.checkin_time,
         p.window_min, p.timezone,
         coalesce(o.display_name, ''),
         r.local_date
  from parents p
  join daily_runs r
    on r.parent_id = p.id
   and r.local_date = (now() at time zone p.timezone)::date
  left join lateral (
    select fm.display_name from family_members fm
    where fm.family_id = p.family_id and fm.role = 'owner'
    limit 1
  ) o on true
  where p.bot_state = 'active'
    and r.morning_sent_at is not null
    and r.delivery_ok
    and (now() at time zone p.timezone)
        >= (now() at time zone p.timezone)::date::timestamp
           + p.checkin_time + make_interval(mins => p.window_min)
    and not exists (
      select 1 from checkins c
      where c.parent_id = p.id and c.local_date = r.local_date
    )
    and not exists (
      select 1 from escalations e
      where e.parent_id = p.id and e.local_date = r.local_date
    );
$$;

create or replace function mark_morning_sent(p_parent_id uuid, p_delivered boolean)
returns void language sql as $$
  insert into daily_runs (parent_id, local_date, morning_sent_at, delivery_ok)
  values (p_parent_id, parent_local_date(p_parent_id), now(), p_delivered)
  on conflict (parent_id, local_date)
  do update set morning_sent_at = excluded.morning_sent_at,
                delivery_ok = excluded.delivery_ok;
$$;

create or replace function mark_reping_sent(p_parent_id uuid)
returns void language sql as $$
  update daily_runs
     set reping_sent_at = now()
   where parent_id = p_parent_id
     and local_date = parent_local_date(p_parent_id);
$$;

create or replace function create_escalation(p_parent_id uuid)
returns escalations
language plpgsql as $$
declare v_row escalations;
begin
  insert into escalations (parent_id, local_date)
  values (p_parent_id, parent_local_date(p_parent_id))
  returning * into v_row;
  return v_row;
exception when unique_violation then
  return null;
end $$;

create or replace function find_invite(p_code text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'code', i.code,
    'parent_id', i.parent_id,
    'parent_name', p.display_name,
    'address_form', p.address_form,
    'child_name', fm.display_name,
    'child_gender', fm.child_gender
  )
  from invites i
  join parents p on p.id = i.parent_id
  join family_members fm on fm.family_id = i.family_id and fm.user_id = i.created_by
  where i.code = p_code
    and i.expires_at > now()
    and i.bound_at is null;
$$;

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
    'parent_id', v_invite.parent_id,
    'child_name', v_child.display_name,
    'child_gender', v_child.child_gender
  );
end $$;
