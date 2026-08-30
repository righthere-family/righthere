revoke execute on function app_set_subscription(uuid, text, text, timestamptz)
  from anon, authenticated;

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
  order by
    exists(
      select 1 from parents p
      where p.family_id = families.id and p.telegram_user_id is not null
    ) desc,
    created_at desc
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('app_token', v_family.app_token);
end $$;

select cron.unschedule('cleanup-stale-families');

select cron.schedule(
  'cleanup-stale-families',
  '17 3 * * *',
  $job$
    delete from families f
    where f.created_at < now() - interval '30 days'
      and not exists (
        select 1 from parents p
        where p.family_id = f.id and p.telegram_user_id is not null
      )
      and not exists (
        select 1 from subscriptions s where s.family_id = f.id
      )
      and not exists (
        select 1 from invites i
        where i.family_id = f.id and i.bound_at is null and i.expires_at > now()
      )
      and not exists (
        select 1 from invites i
        where i.family_id = f.id and i.bound_at is not null
      );
    delete from auth.users u
    where u.is_anonymous
      and u.created_at < now() - interval '30 days'
      and not exists (select 1 from families f where f.owner_id = u.id);
  $job$
);
