create or replace function ring_family(p_family_id uuid, p_kind text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_token uuid;
begin
  select app_token into v_token from families where id = p_family_id;
  if v_token is null then
    return;
  end if;
  perform realtime.send(
    jsonb_build_object('kind', p_kind),
    'family_update',
    'family:' || v_token,
    false
  );
end $$;

revoke all on function ring_family(uuid, text) from public, anon, authenticated;
