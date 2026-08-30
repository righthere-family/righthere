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
  v_blobs       int;
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

  delete from postcard_blobs b
   where b.family_id = v_parent.family_id
     and not exists (select 1 from postcards c where c.photo_path = b.id::text);
  get diagnostics v_blobs = row_count;

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
      'postcard_blobs',  v_blobs,
      'invites',         v_invites,
      'waitlist',        v_waitlist,
      'events',          v_events
    )
  );
end $$;

revoke all on function erase_parent(uuid) from public, anon, authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'cron' and p.proname = 'schedule'
  ) then
    begin
      perform cron.unschedule('cleanup-postcard-blobs');
    exception when others then
      null;
    end;
    perform cron.schedule('cleanup-postcard-blobs', '23 3 * * *',
                          'select cleanup_postcard_blobs()');
  end if;
end $$;
