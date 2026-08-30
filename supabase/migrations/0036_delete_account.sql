create or replace function app_delete_account(p_app_token uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_role text;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then
    return 'no-family';
  end if;
  select role into v_role
  from family_members
  where family_id = v_family.id and user_id = auth.uid();
  if v_role is null then
    return 'not-member';
  end if;

  if v_role = 'owner' then
    delete from families where id = v_family.id;
    return 'deleted';
  end if;
  delete from family_members where family_id = v_family.id and user_id = auth.uid();
  return 'left';
end $$;

revoke all on function app_delete_account(uuid) from public, anon, authenticated;
grant execute on function app_delete_account(uuid) to anon, authenticated;
