create or replace function app_postcard_upload_path(p_app_token uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;
  return v_family.id::text || '/' || gen_random_uuid()::text || '.jpg';
end $$;

revoke all on function app_postcard_upload_path(uuid) from public, anon, authenticated;
grant execute on function app_postcard_upload_path(uuid) to anon, authenticated;
