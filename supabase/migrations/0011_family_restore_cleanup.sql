create or replace function my_family()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  if auth.uid() is null then
    return null;
  end if;
  select * into v_family
  from families
  where owner_id = auth.uid()
  order by created_at desc
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('app_token', v_family.app_token);
end $$;

revoke all on function my_family() from public, anon;
grant execute on function my_family() to authenticated;

create or replace function app_set_subscription(
  p_app_token uuid,
  p_entitlement text,
  p_product text,
  p_expires_at timestamptz
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  if p_entitlement not in ('premium', 'family') then
    return false;
  end if;
  select * into v_family from families where app_token = p_app_token;
  if not found then
    return false;
  end if;

  insert into subscriptions (family_id, rc_app_user_id, entitlement, status, expires_at, updated_at)
  values (v_family.id, 'storekit:' || p_product, p_entitlement, 'active', p_expires_at, now())
  on conflict (family_id) do update
    set rc_app_user_id = excluded.rc_app_user_id,
        entitlement = excluded.entitlement,
        status = 'active',
        expires_at = excluded.expires_at,
        updated_at = now();
  return true;
end $$;

revoke all on function app_set_subscription(uuid, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function app_set_subscription(uuid, text, text, timestamptz)
  to anon, authenticated;

create extension if not exists pg_cron;

select cron.schedule(
  'cleanup-stale-families',
  '17 3 * * *',
  $job$
    delete from families f
    where f.created_at < now() - interval '30 days'
      and not exists (
        select 1 from parents p
        where p.family_id = f.id and p.telegram_user_id is not null
      );
    delete from auth.users u
    where u.is_anonymous
      and u.created_at < now() - interval '30 days'
      and not exists (select 1 from families f where f.owner_id = u.id);
  $job$
);
