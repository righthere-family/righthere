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

  if p_photo_path is not null then
    if p_photo_path like 'kv\_%' then

      if p_photo_path !~ '^kv_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        return false;
      end if;
    elsif not exists (
      select 1 from postcard_blobs
      where id::text = p_photo_path and family_id = v_family.id
    ) then
      return false;
    end if;
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
    return false;
  end if;

  insert into postcards (family_id, parent_id, author_name, body, photo_path)
  values (v_family.id, p_parent_id, coalesce(v_author, ''), v_body, p_photo_path);
  return true;
end $$;

create or replace function create_escalation(p_parent_id uuid, p_local_date date default null)
returns escalations
language plpgsql as $$
declare v_row escalations;
begin
  insert into escalations (parent_id, local_date)
  values (p_parent_id, coalesce(p_local_date, parent_local_date(p_parent_id)))
  returning * into v_row;
  return v_row;
exception when unique_violation then
  return null;
end $$;

revoke all on function create_escalation(uuid, date) from public, anon, authenticated;

create or replace function erase_parent(p_parent_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_parent      parents%rowtype;
  v_med_events  int;
  v_meds        int;
  v_checkins    int;
  v_daily_runs  int;
  v_escalations int;
  v_digests     int;
  v_messages    int;
  v_stories     int;
  v_postcards   int;
  v_invites     int;
  v_waitlist    int;
  v_events      int;
begin
  select * into v_parent from parents where id = p_parent_id;
  if not found then
    return jsonb_build_object('result', 'unknown_parent');
  end if;

  delete from med_events e using meds m
   where m.id = e.med_id and m.parent_id = v_parent.id;
  get diagnostics v_med_events = row_count;

  delete from meds where parent_id = v_parent.id;
  get diagnostics v_meds = row_count;

  delete from checkins where parent_id = v_parent.id;
  get diagnostics v_checkins = row_count;

  delete from daily_runs where parent_id = v_parent.id;
  get diagnostics v_daily_runs = row_count;

  delete from escalations where parent_id = v_parent.id;
  get diagnostics v_escalations = row_count;

  delete from parent_digests where parent_id = v_parent.id;
  get diagnostics v_digests = row_count;

  delete from parent_messages where parent_id = v_parent.id;
  get diagnostics v_messages = row_count;

  delete from family_stories where parent_id = v_parent.id;
  get diagnostics v_stories = row_count;

  delete from postcards where parent_id = v_parent.id and sent_at is null;
  get diagnostics v_postcards = row_count;

  delete from invites where parent_id = v_parent.id;
  get diagnostics v_invites = row_count;

  if v_parent.telegram_user_id is not null then
    delete from waitlist where telegram_user_id = v_parent.telegram_user_id;
    get diagnostics v_waitlist = row_count;
  else
    v_waitlist := 0;
  end if;

  delete from events
   where family_id = v_parent.family_id
     and name = 'parent_message';
  get diagnostics v_events = row_count;

  update parents
     set bot_state        = 'stopped',
         telegram_user_id = null,
         phone            = null,
         address_form     = null,
         city             = null,
         display_name     = 'Родитель',
         evening_time     = null
   where id = v_parent.id;

  return jsonb_build_object(
    'result',    'erased',
    'parent_id', v_parent.id,
    'family_id', v_parent.family_id,
    'deleted',   jsonb_build_object(
      'med_events',      v_med_events,
      'meds',            v_meds,
      'checkins',        v_checkins,
      'daily_runs',      v_daily_runs,
      'escalations',     v_escalations,
      'parent_digests',  v_digests,
      'parent_messages', v_messages,
      'family_stories',  v_stories,
      'postcards',       v_postcards,
      'invites',         v_invites,
      'waitlist',        v_waitlist,
      'events',          v_events
    )
  );
end $$;

revoke all on function erase_parent(uuid) from public, anon, authenticated;

drop index if exists parents_cron;
create index if not exists parents_active on parents (bot_state) where bot_state = 'active';

create index if not exists parents_family on parents (family_id);

drop index if exists family_stories_parent;

create or replace function cleanup_postcard_blobs()
returns void
language sql as $$
  delete from postcard_blobs where created_at < now() - interval '7 days';
$$;

revoke all on function cleanup_postcard_blobs() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('cleanup-postcard-blobs');
  end if;
exception when others then

  null;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('cleanup-postcard-blobs', '17 3 * * *',
                          'select cleanup_postcard_blobs()');
  end if;
end $$;
