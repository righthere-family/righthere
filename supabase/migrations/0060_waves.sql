create table waves (
  id            uuid primary key default gen_random_uuid(),
  family_id     uuid not null references families(id) on delete cascade,
  parent_id     uuid not null references parents(id) on delete cascade,
  author_name   text not null,
  author_gender text not null default 'son',
  local_date    date not null,
  created_at    timestamptz not null default now(),
  sent_at       timestamptz,
  unique (parent_id, author_name, local_date)
);

create index waves_pending on waves (parent_id) where sent_at is null;

alter table waves enable row level security;

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
  if not found then return false; end if;

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

grant execute on function app_wave(uuid, uuid) to anon, authenticated;

create or replace function waves_due()
returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'wave_id',          w.id,
           'telegram_user_id', p.telegram_user_id,
           'author',           w.author_name,
           'gender',           w.author_gender,
           'lang',             p.lang
         ) order by w.created_at), '[]'::jsonb)
  from waves w
  join parents p on p.id = w.parent_id
  where w.sent_at is null
    and p.telegram_user_id is not null
    and p.bot_state = 'active';
$$;

revoke all on function waves_due() from public, anon, authenticated;
