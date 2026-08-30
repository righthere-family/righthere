create or replace function admin_set_entitlement(p_family_id uuid, p_entitlement text)
returns text
language plpgsql as $$
begin
  if p_entitlement not in ('premium', 'family') then
    return 'bad-entitlement';
  end if;
  if not exists (select 1 from families where id = p_family_id) then
    return 'no-family';
  end if;

  insert into subscriptions (family_id, rc_app_user_id, entitlement, status, expires_at, updated_at)
  values (p_family_id, 'admin-grant', p_entitlement, 'active', null, now())
  on conflict (family_id) do update
    set rc_app_user_id = 'admin-grant',
        entitlement = excluded.entitlement,
        status = 'active',
        expires_at = null,
        updated_at = now();
  return 'ok';
end $$;

create or replace function admin_clear_entitlement(p_family_id uuid)
returns text
language plpgsql as $$
declare
  v_source text;
begin
  select rc_app_user_id into v_source from subscriptions where family_id = p_family_id;
  if not found then
    return 'nothing';
  end if;
  if v_source <> 'admin-grant' and v_source not like 'storekit:%' then
    return 'rc-managed';
  end if;

  delete from subscriptions where family_id = p_family_id;
  return 'ok';
end $$;

revoke all on function admin_set_entitlement(uuid, text)  from public, anon, authenticated;
revoke all on function admin_clear_entitlement(uuid)      from public, anon, authenticated;
