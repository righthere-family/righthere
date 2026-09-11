alter table med_events add column if not exists family_notified_at timestamptz;

create or replace function med_alerts_due()
returns jsonb
language sql stable as $$
  with owners as (
    select distinct on (family_id) family_id, timezone
    from family_members
    where role = 'owner'
    order by family_id, created_at
  ),
  due as (
    select e.id as event_id, p.family_id, p.id as parent_id,
           coalesce(p.address_form, p.display_name) as name,
           m.title as med_title,
           to_char(e.slot, 'HH24:MI') as slot,
           p.lang,
           e.local_date, e.slot as slot_time
    from med_events e
    join meds m on m.id = e.med_id
    join parents p on p.id = m.parent_id
    left join owners o on o.family_id = p.family_id
    where e.status in ('no_answer', 'postponed')
      and e.family_notified_at is null
      and p.bot_state = 'active'
      and p.telegram_user_id is not null
      and e.local_date >= (now() at time zone p.timezone)::date - 1
      and now() >= (e.local_date::timestamp + e.slot) at time zone p.timezone + interval '2 hours'
      and extract(hour from now() at time zone coalesce(o.timezone, p.timezone))::int between 8 and 21
    order by e.local_date, e.slot
    limit 20
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'event_id',  event_id,
           'family_id', family_id,
           'parent_id', parent_id,
           'name',      name,
           'med_title', med_title,
           'slot',      slot,
           'lang',      lang
         ) order by local_date, slot_time), '[]'::jsonb)
  from due;
$$;

revoke all on function med_alerts_due() from public, anon, authenticated;

create or replace function app_meds_week(p_app_token uuid, p_parent_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today  date;
  v_total  int;
  v_taken  int;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;
  v_today := (now() at time zone v_parent.timezone)::date;

  select count(*), count(*) filter (where e.status = 'taken')
    into v_total, v_taken
  from med_events e
  join meds m on m.id = e.med_id
  where m.parent_id = v_parent.id
    and e.local_date between v_today - 6 and v_today;

  return jsonb_build_object('taken', v_taken, 'total', v_total);
end $$;

revoke all on function app_meds_week(uuid, uuid) from public, anon, authenticated;
grant execute on function app_meds_week(uuid, uuid) to anon, authenticated;
