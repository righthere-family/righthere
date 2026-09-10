alter table parents add column if not exists nudge_stage int not null default 0;
alter table parents add column if not exists nudge_hot_at timestamptz;

create or replace function invite_nudges_due()
returns jsonb
language sql stable as $$
  with owners as (
    select distinct on (family_id) family_id, timezone
    from family_members
    where role = 'owner'
    order by family_id, created_at
  ),
  invited as (
    select p.id, p.family_id, p.display_name, p.nudge_stage,
           case
             when p.created_at <= now() - interval '7 days' then 3
             when p.created_at <= now() - interval '3 days' then 2
             when p.created_at <= now() - interval '1 day'  then 1
             else 0
           end as target,
           extract(hour from now() at time zone coalesce(o.timezone, 'UTC'))::int as local_hour
    from parents p
    left join owners o on o.family_id = p.family_id
    where p.bot_state = 'invited'
      and p.telegram_user_id is null
  ),
  hot as (
    select p.id, p.family_id, p.display_name
    from parents p
    where p.bot_state = 'onboarding'
      and p.nudge_hot_at is null
      and (select max(i.bound_at) from invites i where i.parent_id = p.id)
          between now() - interval '2 days' and now() - interval '2 hours'
  ),
  due as (
    select jsonb_build_object('parent_id', id, 'family_id', family_id, 'name', display_name, 'stage', target::text) as row
    from invited
    where target > nudge_stage and local_hour = 19
    union all
    select jsonb_build_object('parent_id', id, 'family_id', family_id, 'name', display_name, 'stage', 'hot')
    from hot
  )
  select coalesce(jsonb_agg(row), '[]'::jsonb) from due;
$$;

revoke all on function invite_nudges_due() from public, anon, authenticated;
