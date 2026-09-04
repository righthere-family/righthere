create or replace function app_parent_invite(p_app_token uuid, p_parent_id uuid)
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
  where id = p_parent_id and family_id = v_family.id and telegram_user_id is null;
  if not found then return null; end if;

  select code into v_code
  from invites
  where parent_id = v_parent.id and bound_at is null and expires_at > now()
  order by expires_at desc
  limit 1;

  if v_code is null then
    v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
    insert into invites (code, family_id, parent_id, created_by)
    values (v_code, v_family.id, v_parent.id, v_family.owner_id);
  end if;

  return jsonb_build_object('invite_code', v_code);
end $$;

revoke all on function app_parent_invite(uuid, uuid) from public, anon, authenticated;
grant execute on function app_parent_invite(uuid, uuid) to anon, authenticated;
