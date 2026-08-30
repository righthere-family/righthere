alter table family_members
  add column if not exists apns_env text not null default 'prod'
    check (apns_env in ('prod', 'sandbox'));

create or replace function app_set_push_token(
  p_app_token uuid,
  p_token text,
  p_env text,
  p_timezone text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family_id uuid;
begin
  if p_env not in ('prod', 'sandbox') then
    return false;
  end if;
  select id into v_family_id from families where app_token = p_app_token;
  if not found then
    return false;
  end if;

  update family_members
     set apns_token = p_token,
         apns_env = p_env,
         timezone = coalesce(nullif(p_timezone, ''), timezone)
   where family_id = v_family_id
     and user_id = auth.uid();
  return found;
end $$;

revoke all on function app_set_push_token(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function app_set_push_token(uuid, text, text, text)
  to anon, authenticated;

create or replace function push_targets(p_family_id uuid)
returns table (user_id uuid, apns_token text, apns_env text, tz text)
language sql stable as $$
  select m.user_id, m.apns_token, m.apns_env, m.timezone
  from family_members m
  where m.family_id = p_family_id
    and m.apns_token is not null;
$$;

revoke all on function push_targets(uuid) from public, anon, authenticated;
