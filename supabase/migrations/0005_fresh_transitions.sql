create or replace function record_checkin(
  p_telegram_user_id bigint,
  p_status text,
  p_source text
) returns jsonb
language plpgsql as $$
declare
  v_parent    parents%rowtype;
  v_today     date;
  v_existing  checkins%rowtype;
  v_escalated boolean := false;
  v_result    text := 'ok';
  v_streak    int := 0;
  v_milestone int;
begin
  select * into v_parent from parents where telegram_user_id = p_telegram_user_id;
  if not found then
    return jsonb_build_object('result', 'unknown_parent');
  end if;

  v_today := (now() at time zone v_parent.timezone)::date;

  select * into v_existing from checkins
    where parent_id = v_parent.id and local_date = v_today;

  if found then
    if v_existing.status = 'not_ok' and p_status = 'ok' then
      update checkins
         set status = 'ok', source = p_source, not_ok_kind = null, free_text = null
       where id = v_existing.id;
      v_result := 'upgraded';
    elsif v_existing.status in ('ok', 'accidental_ok') and p_status = 'not_ok' then
      update checkins
         set status = 'not_ok', source = p_source, not_ok_kind = null, free_text = null
       where id = v_existing.id;
      v_result := 'worsened';
    else
      return jsonb_build_object('result', 'duplicate');
    end if;
  else
    begin
      insert into checkins (parent_id, local_date, status, source)
      values (v_parent.id, v_today, p_status, p_source);
    exception when unique_violation then
      return jsonb_build_object('result', 'duplicate');
    end;
  end if;

  update escalations
     set state = 'resolved_by_parent', resolved_at = now()
   where parent_id = v_parent.id
     and local_date = v_today
     and state in ('reping_sent', 'children_notified');
  v_escalated := found;

  select count(*) into v_streak from (
    select local_date, row_number() over (order by local_date desc) as rn
    from checkins
    where parent_id = v_parent.id
      and status in ('ok', 'accidental_ok')
      and local_date <= v_today
  ) t
  where t.local_date = v_today - (t.rn - 1)::int;

  if p_status = 'ok' and v_streak in (7, 30, 100, 365) then
    v_milestone := v_streak;
  end if;

  return jsonb_build_object(
    'result', v_result,
    'was_escalated', v_escalated,
    'streak', v_streak,
    'milestone', v_milestone,
    'parent_id', v_parent.id,
    'family_id', v_parent.family_id
  );
end $$;

revoke all on function record_checkin(bigint, text, text) from public, anon, authenticated;
