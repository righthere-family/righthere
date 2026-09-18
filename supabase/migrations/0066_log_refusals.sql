create or replace function log_refusal(
  p_app_token uuid,
  p_action text,
  p_reason text,
  p_parent_id uuid default null
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_family_id uuid;
  v_detail    text;
begin
  select id into v_family_id from families where app_token = p_app_token;
  if v_family_id is null then return; end if;

  v_detail := p_action || ': ' || p_reason
    || ' · family ' || left(v_family_id::text, 8)
    || coalesce(' · parent ' || left(p_parent_id::text, 8), '')
    || coalesce(' · user ' || left(auth.uid()::text, 8), '');

  if exists (select 1 from bot_events
             where kind = 'refused' and detail = v_detail
               and at > now() - interval '1 minute') then
    return;
  end if;

  insert into bot_events (level, kind, detail) values ('warn', 'refused', v_detail);
end $$;

revoke all on function log_refusal(uuid, text, text, uuid) from public, anon, authenticated;

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
  v_parent parents%rowtype;
  v_member family_members%rowtype;
  v_body   text;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  v_body := trim(coalesce(p_body, ''));
  if v_body = '' and p_photo_path is null then
    perform log_refusal(p_app_token, 'postcard', 'nothing to send', p_parent_id);
    return false;
  end if;
  if length(v_body) > 500 then
    perform log_refusal(p_app_token, 'postcard', 'text longer than 500 characters', p_parent_id);
    return false;
  end if;

  if p_photo_path is not null then
    if p_photo_path like 'kv\_%' then
      if p_photo_path !~ '^kv_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        perform log_refusal(p_app_token, 'postcard', 'malformed photo key', p_parent_id);
        return false;
      end if;
    elsif not exists (
      select 1 from postcard_blobs
      where id::text = p_photo_path and family_id = v_family.id
    ) then
      perform log_refusal(p_app_token, 'postcard', 'photo not found in this family', p_parent_id);
      return false;
    end if;
  end if;

  select * into v_parent from parents where id = p_parent_id and family_id = v_family.id;
  if not found then
    perform log_refusal(p_app_token, 'postcard', 'parent not in this family', p_parent_id);
    return false;
  end if;
  if v_parent.telegram_user_id is null then
    perform log_refusal(p_app_token, 'postcard', 'parent has not connected the bot', p_parent_id);
    return false;
  end if;
  if v_parent.bot_state = 'archived' then
    perform log_refusal(p_app_token, 'postcard', 'reminders are off for this parent', p_parent_id);
    return false;
  end if;

  v_member := family_join_caller(v_family.id);
  if v_member.user_id is null then
    perform log_refusal(p_app_token, 'postcard', 'no signed-in session', p_parent_id);
    return false;
  end if;

  insert into postcards (family_id, parent_id, author_name, body, photo_path)
  values (v_family.id, p_parent_id, coalesce(v_member.display_name, ''), v_body, p_photo_path);
  return true;
end $$;

create or replace function app_store_postcard_photo(p_app_token uuid, p_data text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_bytes  bytea;
  v_id     uuid;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  if (select count(*) from postcard_blobs
      where family_id = v_family.id
        and created_at > now() - interval '24 hours') >= 30 then
    perform log_refusal(p_app_token, 'postcard photo', 'daily limit of 30 photos reached');
    return null;
  end if;

  v_bytes := decode(p_data, 'base64');
  if octet_length(v_bytes) = 0 or octet_length(v_bytes) > 5000000 then
    perform log_refusal(p_app_token, 'postcard photo', 'size ' || octet_length(v_bytes) || ' bytes is out of range');
    return null;
  end if;

  insert into postcard_blobs (family_id, bytes)
  values (v_family.id, v_bytes)
  returning id into v_id;
  return v_id;
end $$;

create or replace function app_wave(p_app_token uuid, p_parent_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_member family_members%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  select * into v_parent from parents
  where id = p_parent_id and family_id = v_family.id and telegram_user_id is not null;
  if not found then
    perform log_refusal(p_app_token, 'wave', 'parent not in this family or not connected', p_parent_id);
    return false;
  end if;

  select * into v_member from family_members
  where family_id = v_family.id and user_id = auth.uid()
  limit 1;
  if not found then
    select * into v_member from family_members
    where family_id = v_family.id and role = 'owner'
    limit 1;
  end if;

  insert into waves (family_id, parent_id, author_name, author_gender, local_date)
  values (v_family.id, v_parent.id,
          coalesce(v_member.display_name, ''),
          coalesce(v_member.child_gender, 'son'),
          parent_local_date(v_parent.id))
  on conflict do nothing;
  return true;
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
  if v_parent.id is null then
    perform log_refusal(p_app_token, 'med add', 'parent not in this family', p_parent_id);
    return null;
  end if;
  if nullif(trim(p_title), '') is null or coalesce(cardinality(p_times), 0) = 0 then
    perform log_refusal(p_app_token, 'med add', 'empty title or no times', v_parent.id);
    return null;
  end if;
  if family_entitlement(p_app_token) is null
     and exists (select 1 from meds where parent_id = v_parent.id and active) then
    perform log_refusal(p_app_token, 'med add', 'free plan allows one medication per parent', v_parent.id);
    return null;
  end if;

  insert into meds (parent_id, title, human_text, times)
  values (v_parent.id, trim(p_title), trim(p_title), p_times)
  returning * into v_med;

  return jsonb_build_object('id', v_med.id);
end $$;

create or replace function app_set_window(
  p_app_token uuid,
  p_parent_id uuid,
  p_minutes int
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  if p_minutes is null or p_minutes not between 60 and 360 then
    perform log_refusal(p_app_token, 'window', coalesce(p_minutes::text, 'no') || ' minutes is out of range', p_parent_id);
    return false;
  end if;
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then
    perform log_refusal(p_app_token, 'window', 'parent not in this family', p_parent_id);
    return false;
  end if;
  if p_minutes <> 180 and family_entitlement(p_app_token) is null then
    perform log_refusal(p_app_token, 'window', 'a custom window needs a plan', v_parent.id);
    return false;
  end if;
  update parents set window_min = p_minutes where id = v_parent.id;
  return true;
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
  if v_parent.id is null then
    perform log_refusal(p_app_token, 'evening', 'parent not in this family', p_parent_id);
    return false;
  end if;
  if p_time is not null and family_entitlement(p_app_token) is null then
    perform log_refusal(p_app_token, 'evening', 'the evening question needs a plan', v_parent.id);
    return false;
  end if;
  update parents set evening_time = p_time where id = v_parent.id;
  return true;
end $$;

create or replace function app_date_add(
  p_app_token uuid,
  p_title text,
  p_month int,
  p_day int
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_id uuid;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;
  if family_entitlement(p_app_token) is null then
    perform log_refusal(p_app_token, 'date add', 'important dates need a plan');
    return null;
  end if;
  if nullif(trim(p_title), '') is null then
    perform log_refusal(p_app_token, 'date add', 'empty title');
    return null;
  end if;
  if (select count(*) from family_dates where family_id = v_family.id) >= 20 then
    perform log_refusal(p_app_token, 'date add', 'limit of 20 dates reached');
    return null;
  end if;
  insert into family_dates (family_id, title, month, day)
  values (v_family.id, trim(p_title), p_month, p_day)
  returning id into v_id;
  return v_id;
end $$;

create or replace function app_set_pause(p_app_token uuid, p_parent_id uuid, p_until date default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today  date;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then
    perform log_refusal(p_app_token, 'pause', 'parent not in this family', p_parent_id);
    return false;
  end if;
  if v_parent.bot_state not in ('active', 'paused') then
    perform log_refusal(p_app_token, 'pause', 'bot state is ' || v_parent.bot_state, v_parent.id);
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
      perform log_refusal(p_app_token, 'pause', 'end date ' || p_until || ' is out of range', v_parent.id);
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

create or replace function app_archive_parent(p_app_token uuid, p_parent_id uuid, p_archived boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then
    perform log_refusal(p_app_token, 'archive', 'parent not in this family', p_parent_id);
    return false;
  end if;
  if v_parent.bot_state = 'demo' then
    perform log_refusal(p_app_token, 'archive', 'the demo parent stays on', v_parent.id);
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
