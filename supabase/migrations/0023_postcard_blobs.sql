create table if not exists postcard_blobs (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references families(id) on delete cascade,
  bytes      bytea not null,
  created_at timestamptz not null default now()
);

alter table postcard_blobs enable row level security;

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

  if p_photo_path is not null and not exists (
    select 1 from postcard_blobs
    where id = p_photo_path::uuid and family_id = v_family.id
  ) then
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

create or replace function cleanup_postcard_blobs()
returns void
language sql as $$
  delete from postcard_blobs b
  where b.created_at < now() - interval '7 days'
    and not exists (select 1 from postcards c
                    where c.photo_path = b.id::text and c.sent_at is null);
$$;

revoke all on function app_send_postcard(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function cleanup_postcard_blobs()                  from public, anon, authenticated;
grant execute on function app_send_postcard(uuid, uuid, text, text) to anon, authenticated;
