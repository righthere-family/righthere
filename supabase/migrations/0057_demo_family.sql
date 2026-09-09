alter table parents drop constraint parents_bot_state_check;
alter table parents add constraint parents_bot_state_check
  check (bot_state in ('invited', 'onboarding', 'active', 'paused', 'stopped', 'blocked', 'demo'));

alter table families add column if not exists demo boolean not null default false;

create or replace function demo_seed(
  p_owner uuid,
  p_child_name text,
  p_parent_name text,
  p_city text,
  p_timezone text,
  p_lang text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_today  date;
  v_day    date;
  v_n      int;
  v_med1   uuid;
  v_med2   uuid;
  v_notes  text[] := array[
    'A grey morning, but nothing serious.',
    'My back is acting up, I will rest today.',
    'Just one of those days.'
  ];
  v_kinds  text[] := array['mood', 'health', 'just_day'];
  v_msgs   text[] := array[
    'Good morning! Slept well, the garden is full of birds today.',
    'Went for a walk by the river, the weather is lovely.',
    'Baked your favourite apple pie, wish you were here for a slice.',
    'The neighbours dropped by for tea. All good here.',
    'Doctor''s visit went fine, pressure is normal.',
    'Watching the old photos again. Call when you have a minute, no rush.'
  ];
  v_gaps   int[] := array[1, 3, 6, 10, 14, 19];
begin
  select * into v_family from families where demo limit 1;
  if found then
    return v_family.app_token;
  end if;

  insert into families (owner_id, demo) values (p_owner, true) returning * into v_family;

  insert into family_members (family_id, user_id, role, child_gender, display_name, timezone)
  values (v_family.id, p_owner, 'owner', 'son', p_child_name, p_timezone);

  insert into parents (family_id, kind, gender, display_name, address_form, city, timezone,
                       checkin_time, window_min, telegram_user_id, bot_state, lang)
  values (v_family.id, 'mom', 'f', p_parent_name, p_parent_name, p_city, p_timezone,
          time '09:00', 180, 1000000000001, 'demo', p_lang)
  returning * into v_parent;

  v_today := (now() at time zone p_timezone)::date;

  for v_n in 1..60 loop
    continue when v_n % 13 = 0;
    v_day := v_today - v_n;
    insert into checkins (parent_id, local_date, status, source, not_ok_kind, free_text, created_at,
                          evening_status, evening_at)
    values (
      v_parent.id,
      v_day,
      case when v_n % 9 = 0 then 'not_ok' else 'ok' end,
      case when v_n % 4 = 0 then 'text' else 'button' end,
      case when v_n % 9 = 0 then v_kinds[1 + (v_n / 9) % 3] end,
      case when v_n % 9 = 0 then v_notes[1 + (v_n / 9) % 3] end,
      ((v_day + time '09:00') + make_interval(mins => 4 + (v_n * 7) % 38)) at time zone p_timezone,
      case when v_n % 2 = 0 then 'ok' end,
      case when v_n % 2 = 0
           then ((v_day + time '20:00') + make_interval(mins => (v_n * 11) % 50)) at time zone p_timezone end
    );
  end loop;

  insert into meds (parent_id, title, human_text, times)
  values (v_parent.id, 'Blood pressure pill', 'Blood pressure pill', array[time '09:30'])
  returning id into v_med1;
  insert into meds (parent_id, title, human_text, times)
  values (v_parent.id, 'Vitamin D', 'Vitamin D', array[time '10:00'])
  returning id into v_med2;

  for v_n in 1..30 loop
    continue when v_n % 13 = 0;
    v_day := v_today - v_n;
    if v_n % 7 <> 3 then
      insert into med_events (med_id, local_date, slot, status, created_at)
      values (v_med1, v_day, time '09:30', 'taken',
              ((v_day + time '09:30') + make_interval(mins => (v_n * 5) % 25)) at time zone p_timezone);
    end if;
    if v_n % 5 <> 2 then
      insert into med_events (med_id, local_date, slot, status, created_at)
      values (v_med2, v_day, time '10:00', 'taken',
              ((v_day + time '10:00') + make_interval(mins => (v_n * 3) % 20)) at time zone p_timezone);
    end if;
  end loop;

  for v_n in 1..6 loop
    insert into parent_messages (family_id, parent_id, kind, body, created_at)
    values (v_family.id, v_parent.id, 'text', v_msgs[v_n],
            ((v_today - v_gaps[v_n] + time '10:10') + make_interval(mins => (v_n * 13) % 45)) at time zone p_timezone);
  end loop;

  insert into family_dates (family_id, title, month, day)
  values (v_family.id, 'Mom''s birthday',
          extract(month from v_today + 21)::int, extract(day from v_today + 21)::int);

  insert into family_stories (family_id, parent_id, question, asked_at, week_start, answer_text, answered_at)
  values
    (v_family.id, v_parent.id,
     'What did you dream of becoming when you were little?',
     (v_today - 16)::timestamp at time zone p_timezone, date_trunc('week', v_today - 16)::date,
     'A geography teacher. I had a globe by my bed and spun it every night before sleep.',
     (v_today - 15 + time '19:20') at time zone p_timezone),
    (v_family.id, v_parent.id,
     'What song reminds you of your youth?',
     (v_today - 9)::timestamp at time zone p_timezone, date_trunc('week', v_today - 9)::date,
     '"Those Were the Days". We danced to it at the school leaving party, and I still know every word.',
     (v_today - 8 + time '18:05') at time zone p_timezone);

  return v_family.app_token;
end $$;

create or replace function demo_tick()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_p      parents%rowtype;
  v_local  timestamp;
  v_date   date;
  v_doy    int;
  v_jitter int;
  v_status text;
  v_name   text;
  v_events jsonb := '[]'::jsonb;
  v_msgs   text[] := array[
    'Good morning! Slept well, the garden is full of birds today.',
    'Went for a walk by the river, the weather is lovely.',
    'Baked your favourite apple pie, wish you were here for a slice.',
    'The neighbours dropped by for tea. All good here.',
    'Doctor''s visit went fine, pressure is normal.',
    'Watching the old photos again. Call when you have a minute, no rush.',
    'Bought new curtains for the kitchen, the yellow ones.',
    'Everything is fine. Hugs to all of you.'
  ];
begin
  for v_p in select * from parents where bot_state = 'demo' loop
    v_local  := now() at time zone v_p.timezone;
    v_date   := v_local::date;
    v_doy    := extract(doy from v_date)::int;
    v_jitter := 3 + (v_doy * 7) % 40;
    v_name   := coalesce(v_p.address_form, v_p.display_name);

    if v_local::time >= v_p.checkin_time + make_interval(mins => v_jitter)
       and not exists (select 1 from checkins where parent_id = v_p.id and local_date = v_date) then
      v_status := case when v_doy % 9 = 0 then 'not_ok' else 'ok' end;
      insert into checkins (parent_id, local_date, status, source, not_ok_kind, free_text)
      values (v_p.id, v_date, v_status, 'button',
              case when v_status = 'not_ok' then 'just_day' end,
              case when v_status = 'not_ok' then 'Just one of those days.' end);
      v_events := v_events || jsonb_build_object(
        'family_id', v_p.family_id, 'name', v_name, 'kind', 'checkin', 'status', v_status);
    end if;

    if v_doy % 3 = 0
       and v_local::time >= v_p.checkin_time + make_interval(mins => v_jitter + 65)
       and not exists (
         select 1 from parent_messages
         where parent_id = v_p.id
           and created_at >= (v_date::timestamp at time zone v_p.timezone)) then
      insert into parent_messages (family_id, parent_id, kind, body)
      values (v_p.family_id, v_p.id, 'text', v_msgs[1 + (v_doy / 3) % array_length(v_msgs, 1)]);
      v_events := v_events || jsonb_build_object(
        'family_id', v_p.family_id, 'name', v_name, 'kind', 'message');
    end if;
  end loop;
  return v_events;
end $$;

revoke all on function demo_seed(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function demo_tick() from public, anon, authenticated;

select demo_seed('e6bf7098-f1cc-49e8-b732-69d4fe9226a3', 'Artem', 'Test Mother', 'Lisbon', 'Europe/Lisbon', 'en');
