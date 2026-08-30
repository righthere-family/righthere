create or replace function app_store_postcard_photo(p_app_token uuid, p_data text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_bytes  bytea;
  v_id     uuid;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  v_bytes := decode(p_data, 'base64');
  if octet_length(v_bytes) = 0 or octet_length(v_bytes) > 5000000 then
    return null;
  end if;

  insert into postcard_blobs (family_id, bytes)
  values (v_family.id, v_bytes)
  returning id into v_id;
  return v_id;
end $$;

revoke all on function app_store_postcard_photo(uuid, text) from public, anon, authenticated;
grant execute on function app_store_postcard_photo(uuid, text) to anon, authenticated;
