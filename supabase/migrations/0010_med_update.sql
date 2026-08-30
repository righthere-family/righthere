create or replace function app_med_update(
  p_app_token uuid,
  p_med_id uuid,
  p_title text,
  p_times time[]
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_updated boolean;
begin
  if nullif(trim(p_title), '') is null or cardinality(p_times) = 0 then
    return false;
  end if;

  update meds m
     set title = trim(p_title),
         human_text = trim(p_title),
         times = p_times
    from parents p, families f
   where m.id = p_med_id
     and m.parent_id = p.id
     and p.family_id = f.id
     and f.app_token = p_app_token;
  v_updated := found;
  return v_updated;
end $$;

revoke all on function app_med_update(uuid, uuid, text, time[]) from public, anon, authenticated;
grant execute on function app_med_update(uuid, uuid, text, time[]) to anon, authenticated;
