create table if not exists parent_messages (
  id            uuid primary key default gen_random_uuid(),
  family_id     uuid not null references families(id) on delete cascade,
  parent_id     uuid not null references parents(id) on delete cascade,
  kind          text not null check (kind in ('text','voice','photo')),
  body          text,
  voice_file_id text,
  photo_file_id text,
  created_at    timestamptz not null default now()
);

create index if not exists parent_messages_family
  on parent_messages (family_id, created_at desc);

alter table parent_messages enable row level security;

create or replace function app_parent_messages(
  p_app_token uuid,
  p_limit int default 50
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_limit  int;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id',            m.id,
      'parent_id',     m.parent_id,
      'kind',          m.kind,
      'body',          m.body,
      'voice_file_id', m.voice_file_id,
      'photo_file_id', m.photo_file_id,
      'created_at',    iso_utc(m.created_at)
    )) order by m.created_at desc)
    from (
      select * from parent_messages
      where family_id = v_family.id
      order by created_at desc
      limit v_limit
    ) m
  ), '[]'::jsonb);
end $$;

update events e
   set family_id = null
 where e.family_id is not null
   and not exists (select 1 from families f where f.id = e.family_id);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'events_family_id_fkey'
      and conrelid = 'public.events'::regclass
  ) then
    alter table events
      add constraint events_family_id_fkey
      foreign key (family_id) references families(id) on delete cascade;
  end if;
end $$;

create index if not exists events_family on events (family_id);

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

  update parents
     set bot_state        = 'stopped',
         telegram_user_id = null,
         phone            = null,
         address_form     = null
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
      'postcards',       v_postcards
    )
  );
end $$;

create index if not exists parents_cron on parents (bot_state)
  where bot_state = 'active' and telegram_user_id is not null;

create index if not exists meds_parent on meds (parent_id);

create index if not exists med_events_postponed
  on med_events (status, last_reminded_at) where status = 'postponed';

create index if not exists family_stories_family on family_stories (family_id);
create index if not exists family_stories_parent on family_stories (parent_id);

create index if not exists invites_parent on invites (parent_id);
create index if not exists invites_family on invites (family_id);

create index if not exists family_dates_family on family_dates (family_id);

create index if not exists families_owner on families (owner_id);

create index if not exists checkins_local_date on checkins (local_date);

revoke all on function app_parent_messages(uuid, int) from public, anon, authenticated;
revoke all on function erase_parent(uuid)             from public, anon, authenticated;
grant execute on function app_parent_messages(uuid, int) to anon, authenticated;
