insert into storage.buckets (id, name, public)
values ('postcards', 'postcards', false)
on conflict (id) do nothing;

create policy postcards_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'postcards'
    and is_family_member(((storage.foldername(name))[1])::uuid)
  );

alter table postcards add column if not exists photo_path text;

drop function if exists app_send_postcard(uuid, uuid, text);

create or replace function app_send_postcard(
  p_app_token uuid,
  p_parent_id uuid,
  p_body text,
  p_photo_path text default null
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_author text;
  v_body   text;
begin
  v_body := trim(coalesce(p_body, ''));
  if (v_body = '' and p_photo_path is null) or length(v_body) > 500 then
    return false;
  end if;

  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  if p_photo_path is not null
     and split_part(p_photo_path, '/', 1) <> v_family.id::text then
    return false;
  end if;

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

  insert into postcards (family_id, parent_id, author_name, body, photo_path)
  values (v_family.id, p_parent_id, coalesce(v_author, ''), v_body, p_photo_path);
  return true;
end $$;

drop function if exists postcards_due();
create or replace function postcards_due()
returns table (
  postcard_id      uuid,
  telegram_user_id bigint,
  author_name      text,
  body             text,
  photo_path       text
)
language sql stable as $$
  select c.id, p.telegram_user_id, c.author_name, c.body, c.photo_path
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

alter table parents    add column if not exists evening_time time;
alter table checkins   add column if not exists evening_status text
  check (evening_status in ('ok', 'not_ok'));
alter table checkins   add column if not exists evening_at timestamptz;
alter table daily_runs add column if not exists evening_sent_at timestamptz;

create or replace function parents_due_for_evening()
returns table (
  parent_id        uuid,
  family_id        uuid,
  telegram_user_id bigint,
  address_form     text,
  display_name     text,
  local_date       date
)
language sql stable as $$
  select p.id, p.family_id, p.telegram_user_id,
         p.address_form, p.display_name,
         (now() at time zone p.timezone)::date
  from parents p
  where p.bot_state = 'active'
    and p.telegram_user_id is not null
    and p.evening_time is not null
    and (now() at time zone p.timezone)::time >= p.evening_time
    and (now() at time zone p.timezone)::time <  p.evening_time + interval '10 minutes'
    and not exists (
      select 1 from daily_runs r
      where r.parent_id = p.id
        and r.local_date = (now() at time zone p.timezone)::date
        and r.evening_sent_at is not null
    );
$$;

create or replace function mark_evening_sent(p_parent_id uuid, p_local_date date)
returns void
language sql as $$
  insert into daily_runs (parent_id, local_date, evening_sent_at)
  values (p_parent_id, p_local_date, now())
  on conflict (parent_id, local_date) do update set evening_sent_at = now();
$$;

create or replace function record_evening(
  p_telegram_user_id bigint,
  p_status text
)
returns uuid
language plpgsql as $$
declare
  v_parent parents%rowtype;
  v_today  date;
begin
  if p_status not in ('ok', 'not_ok') then return null; end if;
  select * into v_parent from parents where telegram_user_id = p_telegram_user_id;
  if not found then return null; end if;
  v_today := (now() at time zone v_parent.timezone)::date;

  insert into checkins (parent_id, local_date, status, source, evening_status, evening_at)
  values (v_parent.id, v_today, p_status, 'button', p_status, now())
  on conflict (parent_id, local_date) do update
    set evening_status = excluded.evening_status,
        evening_at = excluded.evening_at;
  return v_parent.family_id;
end $$;

create or replace function app_set_evening_time(
  p_app_token uuid,
  p_parent_id uuid,
  p_time time
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return false; end if;
  update parents set evening_time = p_time where id = v_parent.id;
  return true;
end $$;

create or replace function app_trends(p_app_token uuid, p_parent_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today date;
  v_recent_minutes numeric;
  v_before_minutes numeric;
  v_recent_missed int;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;
  v_today := (now() at time zone v_parent.timezone)::date;

  select avg(extract(epoch from (c.created_at at time zone v_parent.timezone)::time) / 60)
  into v_recent_minutes
  from checkins c
  where c.parent_id = v_parent.id
    and c.status in ('ok', 'accidental_ok')
    and c.local_date >= v_today - 13 and c.local_date <= v_today;

  select avg(extract(epoch from (c.created_at at time zone v_parent.timezone)::time) / 60)
  into v_before_minutes
  from checkins c
  where c.parent_id = v_parent.id
    and c.status in ('ok', 'accidental_ok')
    and c.local_date >= v_today - 43 and c.local_date < v_today - 13;

  select count(*) into v_recent_missed
  from generate_series(greatest(v_today - 29,
                                (v_parent.created_at at time zone v_parent.timezone)::date),
                       v_today - 1, '1 day') as d
  where not exists (select 1 from checkins c
                    where c.parent_id = v_parent.id and c.local_date = d::date);

  return jsonb_build_object(
    'recent_avg_minute', round(v_recent_minutes),
    'before_avg_minute', round(v_before_minutes),
    'shift_minutes', case when v_recent_minutes is null or v_before_minutes is null
                          then null else round(v_recent_minutes - v_before_minutes) end,
    'missed_30d', v_recent_missed
  );
end $$;

create or replace function my_role(p_app_token uuid)
returns text
language sql stable security definer set search_path = public as $$
  select m.role
  from family_members m
  join families f on f.id = m.family_id
  where f.app_token = p_app_token and m.user_id = auth.uid()
  limit 1;
$$;

create or replace function family_entitlement(p_app_token uuid)
returns text
language sql stable security definer set search_path = public as $$
  select s.entitlement
  from subscriptions s
  join families f on f.id = s.family_id
  where f.app_token = p_app_token
    and s.status = 'active'
    and (s.expires_at is null or s.expires_at > now())
  limit 1;
$$;

revoke all on function app_send_postcard(uuid, uuid, text, text)   from public, anon, authenticated;
revoke all on function postcards_due()                             from public, anon, authenticated;
revoke all on function parents_due_for_evening()                   from public, anon, authenticated;
revoke all on function mark_evening_sent(uuid, date)               from public, anon, authenticated;
revoke all on function record_evening(bigint, text)                from public, anon, authenticated;
revoke all on function app_set_evening_time(uuid, uuid, time)      from public, anon, authenticated;
revoke all on function app_trends(uuid, uuid)                      from public, anon, authenticated;
revoke all on function my_role(uuid)                               from public, anon, authenticated;
revoke all on function family_entitlement(uuid)                    from public, anon, authenticated;
grant execute on function app_send_postcard(uuid, uuid, text, text) to anon, authenticated;
grant execute on function app_set_evening_time(uuid, uuid, time)    to anon, authenticated;
grant execute on function app_trends(uuid, uuid)                    to anon, authenticated;
grant execute on function my_role(uuid)                             to anon, authenticated;
grant execute on function family_entitlement(uuid)                  to anon, authenticated;
