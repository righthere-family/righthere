create or replace function my_family()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  if auth.uid() is null then
    return null;
  end if;
  select f.* into v_family
  from families f
  where f.owner_id = auth.uid()
     or exists (
       select 1 from family_members m
       where m.family_id = f.id and m.user_id = auth.uid()
     )
  order by
    f.demo,
    exists (
      select 1 from parents p
      where p.family_id = f.id and p.telegram_user_id is not null
    ) desc,
    (f.owner_id = auth.uid()) desc,
    coalesce((
      select max(m.created_at) from family_members m
      where m.family_id = f.id and m.user_id = auth.uid()
    ), f.created_at) desc
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('app_token', v_family.app_token);
end $$;
