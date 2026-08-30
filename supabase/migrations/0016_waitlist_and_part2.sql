create table if not exists waitlist (
  telegram_user_id bigint primary key,
  username         text,
  first_name       text,
  source           text not null default 'beta',
  invited_at       timestamptz,
  created_at       timestamptz not null default now()
);

alter table waitlist enable row level security;

create or replace function set_checkin_time(p_telegram_user_id bigint, p_time time)
returns uuid
language plpgsql as $$
declare
  v_family uuid;
begin
  update parents
     set checkin_time = p_time
   where telegram_user_id = p_telegram_user_id
     and bot_state in ('active', 'paused')
  returning family_id into v_family;
  return v_family;
end $$;

create table if not exists parent_digests (
  parent_id  uuid not null references parents(id) on delete cascade,
  week_start date not null,
  sent_at    timestamptz not null default now(),
  primary key (parent_id, week_start)
);

alter table parent_digests enable row level security;

create or replace function parents_due_for_digest()
returns table (
  parent_id          uuid,
  telegram_user_id   bigint,
  address_form       text,
  display_name       text,
  child_display_name text,
  ok_days            int,
  covered_days       int,
  week_start         date
)
language sql stable as $$
  with due as (
    select p.id,
           p.telegram_user_id,
           p.address_form,
           p.display_name,
           p.family_id,
           (now() at time zone p.timezone)::date                       as local_date,
           date_trunc('week', (now() at time zone p.timezone))::date   as week_start,
           (p.created_at at time zone p.timezone)::date                as started_on
    from parents p
    where p.bot_state = 'active'
      and p.telegram_user_id is not null
      and extract(isodow from (now() at time zone p.timezone))::int = 7
      and (now() at time zone p.timezone)::time >= time '19:00'
      and (now() at time zone p.timezone)::time <  time '19:10'
  )
  select d.id,
         d.telegram_user_id,
         d.address_form,
         d.display_name,
         coalesce(m.display_name, ''),
         (select count(*)::int from checkins c
           where c.parent_id = d.id
             and c.local_date between d.week_start and d.local_date
             and c.status in ('ok', 'accidental_ok')),
         (d.local_date - greatest(d.week_start, d.started_on) + 1)::int,
         d.week_start
  from due d
  left join family_members m on m.family_id = d.family_id and m.role = 'owner'
  where not exists (
          select 1 from parent_digests pd
          where pd.parent_id = d.id and pd.week_start = d.week_start
        )

    and d.local_date - greatest(d.week_start, d.started_on) + 1 >= 3;
$$;

create or replace function mark_digest_sent(p_parent_id uuid, p_week_start date)
returns void
language sql as $$
  insert into parent_digests (parent_id, week_start)
  values (p_parent_id, p_week_start)
  on conflict do nothing;
$$;

revoke all on function set_checkin_time(bigint, time)   from public, anon, authenticated;
revoke all on function parents_due_for_digest()          from public, anon, authenticated;
revoke all on function mark_digest_sent(uuid, date)      from public, anon, authenticated;
