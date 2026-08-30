create or replace function app_new_invite(p_app_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_code   text;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  select * into v_parent
  from parents
  where family_id = v_family.id and telegram_user_id is null
  order by created_at
  limit 1;
  if not found then return null; end if;

  v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  insert into invites (code, family_id, parent_id, created_by)
  values (v_code, v_family.id, v_parent.id, v_family.owner_id);

  return jsonb_build_object('invite_code', v_code);
end $$;

revoke all on function app_new_invite(uuid) from public, anon, authenticated;
grant execute on function app_new_invite(uuid) to anon, authenticated;
