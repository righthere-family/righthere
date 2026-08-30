create extension if not exists pgcrypto;

create table families (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete restrict,
  created_at  timestamptz not null default now()
);

create table family_members (
  family_id   uuid not null references families(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null default 'sibling' check (role in ('owner','sibling')),

  child_gender text not null default 'son' check (child_gender in ('son','daughter')),
  display_name text not null,
  apns_token  text,
  timezone    text not null default 'Europe/Belgrade',
  created_at  timestamptz not null default now(),
  primary key (family_id, user_id)
);

create table parents (
  id            uuid primary key default gen_random_uuid(),
  family_id     uuid not null references families(id) on delete cascade,
  kind          text not null default 'mom' check (kind in ('mom','dad','custom')),
  display_name  text not null,
  address_form  text,
  timezone      text not null,
  checkin_time  time not null default '09:00',
  window_min    int  not null default 180 check (window_min between 60 and 360),
  telegram_user_id bigint unique,
  bot_state     text not null default 'invited'
                check (bot_state in ('invited','onboarding','active','paused','stopped','blocked')),
  paused_until  date,
  created_at    timestamptz not null default now()
);

create table invites (
  code        text primary key,
  family_id   uuid not null references families(id) on delete cascade,
  parent_id   uuid not null references parents(id) on delete cascade,
  created_by  uuid not null references auth.users(id),
  expires_at  timestamptz not null default now() + interval '30 days',
  bound_at    timestamptz
);

create table checkins (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid not null references parents(id) on delete cascade,
  local_date  date not null,
  status      text not null check (status in ('ok','not_ok','accidental_ok')),
  source      text not null default 'button' check (source in ('button','text','voice','reaction','late')),
  not_ok_kind text check (not_ok_kind in ('health','mood','just_day','call_me','private')),
  free_text   text,
  created_at  timestamptz not null default now(),
  unique (parent_id, local_date)
);

create table meds (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid not null references parents(id) on delete cascade,
  title       text not null,
  human_text  text not null,
  times       time[] not null,
  days        int[] not null default '{1,2,3,4,5,6,7}',
  confirm     boolean not null default true,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table med_events (
  id          uuid primary key default gen_random_uuid(),
  med_id      uuid not null references meds(id) on delete cascade,
  local_date  date not null,
  slot        time not null,
  status      text not null check (status in ('taken','postponed','skipped','no_answer')),
  created_at  timestamptz not null default now(),
  unique (med_id, local_date, slot)
);

create table escalations (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid not null references parents(id) on delete cascade,
  local_date  date not null,
  state       text not null default 'reping_sent'
              check (state in ('reping_sent','children_notified','resolved_by_parent','resolved_by_child','expired')),
  delivery_ok boolean not null default true,
  resolved_by uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  unique (parent_id, local_date)
);

create table events (
  id          bigint generated always as identity primary key,
  user_id     uuid,
  family_id   uuid,
  name        text not null,
  props       jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index on events (name, created_at);

create table subscriptions (
  family_id     uuid primary key references families(id) on delete cascade,
  rc_app_user_id text not null,
  entitlement   text not null check (entitlement in ('premium','family')),
  status        text not null,
  expires_at    timestamptz,
  updated_at    timestamptz not null default now()
);

alter table families      enable row level security;
alter table family_members enable row level security;
alter table parents       enable row level security;
alter table invites       enable row level security;
alter table checkins      enable row level security;
alter table meds          enable row level security;
alter table med_events    enable row level security;
alter table escalations   enable row level security;
alter table events        enable row level security;
alter table subscriptions enable row level security;

create or replace function is_family_member(fid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from family_members
    where family_id = fid and user_id = auth.uid()
  );
$$;

create policy family_read   on families for select using (is_family_member(id));
create policy family_insert on families for insert with check (owner_id = auth.uid());

create policy members_read  on family_members for select using (is_family_member(family_id));
create policy members_self  on family_members for insert with check (user_id = auth.uid());
create policy members_update_self on family_members for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy parents_rw on parents for all
  using (is_family_member(family_id)) with check (is_family_member(family_id));

create policy invites_rw on invites for all
  using (is_family_member(family_id)) with check (created_by = auth.uid());

create policy checkins_read on checkins for select
  using (is_family_member((select family_id from parents p where p.id = parent_id)));

create policy meds_rw on meds for all
  using (is_family_member((select family_id from parents p where p.id = parent_id)))
  with check (is_family_member((select family_id from parents p where p.id = parent_id)));

create policy med_events_read on med_events for select
  using (is_family_member((select family_id from parents p, meds m
                           where m.id = med_id and p.id = m.parent_id)));

create policy escalations_read on escalations for select
  using (is_family_member((select family_id from parents p where p.id = parent_id)));
create policy escalations_resolve on escalations for update
  using (is_family_member((select family_id from parents p where p.id = parent_id)))
  with check (resolved_by = auth.uid());

create policy events_insert_own on events for insert with check (user_id = auth.uid());
create policy subs_read on subscriptions for select using (is_family_member(family_id));
