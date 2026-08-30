drop function if exists med_mark(bigint, uuid, time, text);

create or replace function med_mark(
  p_telegram_user_id bigint,
  p_med_id uuid,
  p_slot time,
  p_status text,
  p_local_date date
) returns boolean
language plpgsql as $$
declare
  v_updated boolean;
begin
  if p_status not in ('taken', 'postponed') then
    return false;
  end if;
  update med_events e
     set status = p_status,
         last_reminded_at = now()
    from meds m, parents p
   where e.med_id = p_med_id
     and m.id = e.med_id
     and p.id = m.parent_id
     and p.telegram_user_id = p_telegram_user_id
     and e.local_date = p_local_date
     and e.local_date = (now() at time zone p.timezone)::date
     and e.slot = p_slot;
  v_updated := found;
  return v_updated;
end $$;

revoke all on function med_mark(bigint, uuid, time, text, date) from public, anon, authenticated;
