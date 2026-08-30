create or replace function app_remove_parent(p_app_token uuid, p_parent_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  if (select count(*) from parents where family_id = v_family.id) <= 1 then
    return false;
  end if;

  delete from parents
  where id = p_parent_id and family_id = v_family.id;

  return found;
end $$;

revoke all on function app_remove_parent(uuid, uuid) from public, anon, authenticated;
grant execute on function app_remove_parent(uuid, uuid) to anon, authenticated;
