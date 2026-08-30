alter table parents
  add column lang text not null default 'ru' check (lang in ('ru', 'en'));

alter table bot_texts
  add column lang text not null default 'ru' check (lang in ('ru', 'en'));

drop index if exists bot_texts_group;
create index bot_texts_group on bot_texts (lang, group_key, sort);

alter table story_questions
  add column lang text not null default 'ru' check (lang in ('ru', 'en'));

alter table waitlist
  add column lang text not null default 'ru' check (lang in ('ru', 'en'));

alter table family_members
  add column if not exists push_lang text not null default 'ru'
    check (push_lang in ('ru', 'en'));

insert into bot_texts (group_key, sort, lang, text) values
  ('morning',  1, 'en', 'Good morning, {name}! How are you today?'),
  ('morning',  2, 'en', '{name}, good morning. How did you sleep?'),
  ('morning',  3, 'en', 'Hello, {name}! How are you feeling this morning?'),
  ('morning',  4, 'en', 'Good morning! How is your day starting out?'),
  ('morning',  5, 'en', '{name}, good morning. How are your spirits today?'),
  ('morning',  6, 'en', 'Good morning, {name}! How are you doing?'),
  ('morning',  7, 'en', '{name}, a new day is here. How does it find you?'),
  ('morning',  8, 'en', '{name}, good morning! Is everything calm and well?'),
  ('morning',  9, 'en', '{name}, good morning. May the day be gentle. But first — how are you?'),
  ('morning', 10, 'en', 'Good morning! Is everything all right, {name}?'),
  ('morning', 11, 'en', 'Morning, {name}! How are you feeling?'),
  ('morning', 12, 'en', 'Good morning! Let''s start the day with a good habit. How are you, {name}?'),

  ('ok_reply', 1, 'en', 'Wonderful! Have a lovely day ☀️'),
  ('ok_reply', 2, 'en', 'Lovely. {child} can already see it.'),
  ('ok_reply', 3, 'en', 'Glad to hear it. Until tomorrow!'),
  ('ok_reply', 4, 'en', 'Thank you! Have a peaceful day.'),
  ('ok_reply', 5, 'en', 'Noted ✅ May the day go well.'),
  ('ok_reply', 6, 'en', 'Good! That''s the best news of the morning.'),

  ('reping', 1, 'en', '{name}, I''m still here. How are you today?'),
  ('reping', 2, 'en', '{name}, checking in once more. Is everything all right?'),
  ('reping', 3, 'en', '{name}, the morning is in full swing. How are you?'),

  ('missed', 1, 'en', e'{name}, no word from you yet today — that''s all right, life happens: errands, guests, the phone in another room.\n\n{child} will see that the morning went by without your hello and will most likely call — just to hear your voice.\n\nThe buttons are still down below — tap one when you have a minute.'),

  ('meds', 1, 'en', '{name}, it''s time for your medication: {medication}.'),

  ('evening', 1, 'en', '{name}, how was your day?'),

  ('story_ask', 1, 'en', e'{name}, this week''s question — just for the family''s memory box:\n\n{question}\n\nYou can answer in words or with a voice message, whichever is easier. Or skip it — that''s perfectly fine.'),

  ('digest_full', 1, 'en', '{name}, the week is complete: you checked in on all {days} days. {child} saw it every morning — thank you for that.'),
  ('digest_most', 1, 'en', '{name}, this week you answered {answers} times out of {days}. {child} knew all along that things were going their usual way.'),
  ('digest_few',  1, 'en', '{name}, we hardly saw each other this week. If mornings are an inconvenient time, say /time and I''ll adjust. And if you''d rather I not write at all — say /pause.'),

  ('milestone_7',   1, 'en', 'And by the way: today marks a whole week of us greeting the morning together. {child} gets your hello every day — and it''s the best news of the day.'),
  ('milestone_30',  1, 'en', 'Today makes a month of you being in touch every single day. Thirty calm mornings — for you and for your family. That is worth a lot, {name}.'),
  ('milestone_100', 1, 'en', 'One hundred morning hellos in a row. Some habits make life sturdier — you''ve built one. Thank you for being you, {name} ❤️'),
  ('milestone_365', 1, 'en', 'A whole year, day after day. Such constancy is rare — and a true gift to your family. Happy anniversary, {name} ❤️'),

  ('beta_invite', 1, 'en', e'Hello! This is “Mom, I''m Right Here” — you signed up for the beta, and your turn has come ✅\n\nWhat to do:\n1. Install TestFlight from the App Store: https://apps.apple.com/app/testflight/id899247664\n2. Open the app link inside it: {link}\n3. Add your mom in the app — the bot will explain everything to her from there.\n\nIf anything doesn''t work — just reply to this message.');

insert into story_questions (lang, text, sort) values
  ('en', 'What song takes you straight back to your youth?', 10),
  ('en', 'What dish do you cook better than anyone — and who taught you?', 20),
  ('en', 'Tell me about the funniest thing that ever happened at work.', 30),
  ('en', 'What movie could you rewatch endlessly?', 40),
  ('en', 'What can you make with your own hands that few people still can?', 50),
  ('en', 'How did your family celebrate New Year''s when you were a child?', 60),
  ('en', 'What smell instantly brings back your childhood?', 70),
  ('en', 'What was the biggest fashion when you were twenty?', 80),
  ('en', 'What advice would you give your sixteen-year-old self?', 90),
  ('en', 'Tell me about the most interesting person you have ever met.', 100),
  ('en', 'What book or story left the deepest impression on you?', 110),
  ('en', 'What are you proud of that you made with your own hands?', 120);

drop function if exists create_family_with_parent(text, text, text, time, text, text, text);

create or replace function create_family_with_parent(
  p_parent_name text,
  p_city text,
  p_timezone text,
  p_checkin_time time,
  p_child_name text,
  p_child_gender text,
  p_child_timezone text,
  p_lang text default 'ru'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_code   text;
begin
  if auth.uid() is null then
    return null;
  end if;
  if p_child_gender not in ('son', 'daughter') then
    return null;
  end if;
  if p_lang not in ('ru', 'en') then
    p_lang := 'ru';
  end if;

  insert into families (owner_id) values (auth.uid()) returning * into v_family;

  insert into family_members (family_id, user_id, role, child_gender, display_name, timezone)
  values (v_family.id, auth.uid(), 'owner', p_child_gender,
          coalesce(nullif(trim(p_child_name), ''), 'Ваш ребёнок'), p_child_timezone);

  insert into parents (family_id, kind, display_name, city, timezone, checkin_time, lang)
  values (v_family.id, 'mom',
          coalesce(nullif(trim(p_parent_name), ''), 'Мама'),
          nullif(trim(p_city), ''), p_timezone, p_checkin_time, p_lang)
  returning * into v_parent;

  v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  insert into invites (code, family_id, parent_id, created_by)
  values (v_code, v_family.id, v_parent.id, auth.uid());

  return jsonb_build_object(
    'family_id',   v_family.id,
    'app_token',   v_family.app_token,
    'parent_id',   v_parent.id,
    'invite_code', v_code
  );
end $$;

revoke all on function create_family_with_parent(text, text, text, time, text, text, text, text)
  from public, anon;
grant execute on function create_family_with_parent(text, text, text, time, text, text, text, text)
  to authenticated;

drop function if exists app_add_parent(uuid, text, text, text, text, time);

create or replace function app_add_parent(
  p_app_token    uuid,
  p_display_name text,
  p_kind         text,
  p_city         text,
  p_timezone     text,
  p_checkin_time time,
  p_lang         text default 'ru'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_code   text;
begin
  if p_kind not in ('mom', 'dad', 'custom') then
    return null;
  end if;
  if p_lang not in ('ru', 'en') then
    p_lang := 'ru';
  end if;

  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  if (select count(*) from parents where family_id = v_family.id) >= 6 then
    return null;
  end if;

  insert into parents (family_id, kind, display_name, city, timezone, checkin_time, lang)
  values (v_family.id, p_kind,
          coalesce(nullif(trim(p_display_name), ''), 'Родитель'),
          nullif(trim(p_city), ''), p_timezone, p_checkin_time, p_lang)
  returning * into v_parent;

  v_code := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  insert into invites (code, family_id, parent_id, created_by)
  values (v_code, v_family.id, v_parent.id, v_family.owner_id);

  return jsonb_build_object('parent_id', v_parent.id, 'invite_code', v_code);
end $$;

revoke all on function app_add_parent(uuid, text, text, text, text, time, text)
  from public, anon, authenticated;
grant execute on function app_add_parent(uuid, text, text, text, text, time, text)
  to anon, authenticated;

drop function if exists app_update_parent(uuid, text, text, text, time, text, uuid);

create or replace function app_update_parent(
  p_app_token uuid,
  p_name text,
  p_city text,
  p_timezone text,
  p_checkin_time time,
  p_phone text,
  p_parent_id uuid default null,
  p_lang text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return false; end if;

  update parents
     set display_name = coalesce(nullif(trim(p_name), ''), display_name),
         city         = nullif(trim(p_city), ''),
         timezone     = coalesce(nullif(trim(p_timezone), ''), timezone),
         checkin_time = coalesce(p_checkin_time, checkin_time),
         phone        = nullif(trim(p_phone), ''),

         lang         = coalesce(case when p_lang in ('ru', 'en') then p_lang end, lang)
   where id = v_parent.id;
  return true;
end $$;

revoke all on function app_update_parent(uuid, text, text, text, time, text, uuid, text)
  from public, anon, authenticated;
grant execute on function app_update_parent(uuid, text, text, text, time, text, uuid, text)
  to anon, authenticated;

create or replace function app_parent_card(v_parent parents)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today   date;
  v_checkin checkins%rowtype;
  v_esc     escalations%rowtype;
  v_run     daily_runs%rowtype;
  v_anchor  date;
  v_streak  int := 0;
  v_status  jsonb;
  v_invite  text;
  v_meds_taken int := 0;
  v_meds_total int := 0;
  v_parent_json jsonb;
  v_evening jsonb;
begin
  v_parent_json := jsonb_build_object(
    'id',           v_parent.id,
    'kind',         v_parent.kind,
    'display_name', v_parent.display_name,
    'city',         v_parent.city,
    'phone',        v_parent.phone,
    'timezone',     v_parent.timezone,
    'checkin_time', to_char(v_parent.checkin_time, 'HH24:MI'),
    'window_min',   v_parent.window_min,
    'evening_time', to_char(v_parent.evening_time, 'HH24:MI'),
    'lang',         v_parent.lang
  );

  if v_parent.telegram_user_id is null then
    select code into v_invite
    from invites
    where parent_id = v_parent.id and bound_at is null and expires_at > now()
    order by expires_at desc
    limit 1;

    return jsonb_build_object(
      'parent',      v_parent_json,
      'status',      jsonb_build_object('state', 'waiting_parent'),
      'streak',      0,
      'meds',        jsonb_build_object('taken', 0, 'total', 0),
      'invite_code', v_invite
    );
  end if;

  v_today := (now() at time zone v_parent.timezone)::date;

  select * into v_checkin from checkins    where parent_id = v_parent.id and local_date = v_today;
  select * into v_esc     from escalations where parent_id = v_parent.id and local_date = v_today;
  select * into v_run     from daily_runs  where parent_id = v_parent.id and local_date = v_today;

  v_anchor := case when v_checkin.id is null then v_today - 1 else v_today end;
  select count(*) into v_streak from (
    select local_date, row_number() over (order by local_date desc) as rn
    from checkins
    where parent_id = v_parent.id
      and status in ('ok', 'accidental_ok')
      and local_date <= v_anchor
  ) t
  where t.local_date = v_anchor - (t.rn - 1)::int;

  select coalesce(sum(cardinality(m.times)), 0) into v_meds_total
  from meds m
  where m.parent_id = v_parent.id and m.active
    and extract(isodow from v_today)::int = any(m.days);

  select count(*) into v_meds_taken
  from med_events e
  join meds m on m.id = e.med_id
  where m.parent_id = v_parent.id
    and e.local_date = v_today
    and e.status = 'taken';

  if v_parent.bot_state = 'paused' and v_parent.paused_until is not null
     and v_parent.paused_until >= v_today then
    v_status := jsonb_build_object('state', 'paused', 'until', to_char(v_parent.paused_until, 'YYYY-MM-DD'));
  elsif v_checkin.id is not null and v_checkin.status in ('ok', 'accidental_ok') then
    v_status := jsonb_build_object('state', 'ok', 'at', iso_utc(v_checkin.created_at));
  elsif v_checkin.id is not null then
    v_status := jsonb_build_object(
      'state', 'not_ok',
      'at',    iso_utc(v_checkin.created_at),
      'kind',  v_checkin.not_ok_kind,
      'quote', v_checkin.free_text
    );
  elsif v_esc.id is not null and v_esc.state in ('reping_sent', 'children_notified') then
    v_status := jsonb_build_object('state', 'quiet', 'at', iso_utc(v_esc.created_at));
  elsif v_run.reping_sent_at is not null then
    v_status := jsonb_build_object(
      'state',    'reminded',
      'at',       iso_utc(v_run.reping_sent_at),
      'deadline', iso_utc((v_today::timestamp + v_parent.checkin_time
                           + make_interval(mins => v_parent.window_min)) at time zone v_parent.timezone)
    );
  else
    v_status := jsonb_build_object(
      'state',    'still_morning',
      'usual_by', iso_utc((v_today::timestamp + v_parent.checkin_time) at time zone v_parent.timezone)
    );
  end if;

  if v_checkin.evening_status is not null then
    v_evening := jsonb_build_object(
      'status', v_checkin.evening_status,
      'at',     iso_utc(v_checkin.evening_at)
    );
  end if;

  return jsonb_build_object(
    'parent',  v_parent_json,
    'status',  v_status,
    'streak',  v_streak,
    'meds',    jsonb_build_object('taken', v_meds_taken, 'total', v_meds_total),
    'evening', v_evening
  );
end $$;

revoke all on function app_parent_card(parents) from public, anon, authenticated;

create or replace function find_invite(p_code text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'code', i.code,
    'parent_id', i.parent_id,
    'parent_name', p.display_name,
    'address_form', p.address_form,
    'child_name', fm.display_name,
    'child_gender', fm.child_gender,
    'lang', p.lang
  )
  from invites i
  join parents p on p.id = i.parent_id
  join family_members fm on fm.family_id = i.family_id and fm.user_id = i.created_by
  where i.code = p_code
    and i.expires_at > now()
    and i.bound_at is null;
$$;

create or replace function bind_invite(p_code text, p_telegram_user_id bigint)
returns jsonb
language plpgsql as $$
declare
  v_invite invites%rowtype;
  v_child  family_members%rowtype;
  v_lang   text;
begin
  update invites
     set bound_at = now()
   where code = p_code
     and bound_at is null
     and expires_at > now()
  returning * into v_invite;

  if not found then
    return null;
  end if;

  update parents
     set telegram_user_id = p_telegram_user_id,
         bot_state = 'onboarding'
   where id = v_invite.parent_id
  returning lang into v_lang;

  select * into v_child from family_members
   where family_id = v_invite.family_id and user_id = v_invite.created_by;

  return jsonb_build_object(
    'parent_id',    v_invite.parent_id,
    'family_id',    v_invite.family_id,
    'child_name',   v_child.display_name,
    'child_gender', v_child.child_gender,
    'lang',         v_lang
  );
end $$;

revoke all on function find_invite(text) from public, anon, authenticated;
revoke all on function bind_invite(text, bigint) from public, anon, authenticated;

drop function if exists app_set_push_token(uuid, text, text, text);

create or replace function app_set_push_token(
  p_app_token uuid,
  p_token text,
  p_env text,
  p_timezone text,
  p_lang text default 'ru'
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family_id uuid;
begin
  if p_env not in ('prod', 'sandbox') then
    return false;
  end if;
  if p_lang not in ('ru', 'en') then
    p_lang := 'ru';
  end if;
  select id into v_family_id from families where app_token = p_app_token;
  if not found then
    return false;
  end if;

  update family_members
     set apns_token = p_token,
         apns_env = p_env,
         push_lang = p_lang,
         timezone = coalesce(nullif(p_timezone, ''), timezone)
   where family_id = v_family_id
     and user_id = auth.uid();
  return found;
end $$;

revoke all on function app_set_push_token(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function app_set_push_token(uuid, text, text, text, text)
  to anon, authenticated;

drop function if exists push_targets(uuid);

create or replace function push_targets(p_family_id uuid)
returns table (user_id uuid, apns_token text, apns_env text, tz text, lang text)
language sql stable as $$
  select m.user_id, m.apns_token, m.apns_env, m.timezone, m.push_lang
  from family_members m
  where m.family_id = p_family_id
    and m.apns_token is not null;
$$;

revoke all on function push_targets(uuid) from public, anon, authenticated;

create or replace function cron_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  with snap as (
    select now() as at
  ),

  active as (
    select p.id                                as parent_id,
           p.family_id                         as family_id,
           p.telegram_user_id                  as telegram_user_id,
           p.display_name                      as display_name,
           p.address_form                      as address_form,
           p.checkin_time                      as checkin_time,
           p.window_min                        as window_min,
           p.timezone                          as timezone,
           p.evening_time                      as evening_time,
           p.paused_until                      as paused_until,
           p.created_at                        as created_at,
           p.lang                              as lang,
           coalesce(o.display_name, '')        as child_display_name,
           s.at                                as at,
           (s.at at time zone p.timezone)      as local_ts
    from snap s
    cross join parents p
    left join lateral (
      select fm.display_name from family_members fm
      where fm.family_id = p.family_id and fm.role = 'owner'
      limit 1
    ) o on true
    where p.bot_state = 'active'
  ),

  clock as (
    select a.*,
           a.local_ts::date                                  as local_date,
           a.local_ts::time                                  as local_time,
           extract(isodow from a.local_ts)::int              as local_dow,
           date_trunc('week', a.local_ts)::date              as week_start,
           (a.created_at at time zone a.timezone)::date      as started_on
    from active a
  ),

  today as (
    select c.*,
           (c.local_date::timestamp + c.checkin_time) at time zone c.timezone as checkin_at,
           case when c.evening_time is not null
                then (c.local_date::timestamp + c.evening_time) at time zone c.timezone
           end                                                                as evening_at
    from clock c
  ),

  due_deadline as (
    select distinct on (t.parent_id)
           t.parent_id, t.family_id, t.telegram_user_id,
           t.display_name, t.address_form, t.checkin_time,
           t.window_min, t.timezone, t.child_display_name, t.lang,
           r.local_date as local_date
    from today t
    join daily_runs r
      on r.parent_id = t.parent_id
     and r.local_date between t.local_date - 1 and t.local_date
    cross join lateral (
      select (r.local_date::timestamp + t.checkin_time
              + make_interval(mins => t.window_min)) at time zone t.timezone as deadline_at
    ) d
    where r.morning_sent_at is not null
      and r.delivery_ok
      and t.at >= d.deadline_at
      and t.at <  d.deadline_at + interval '12 hours'
      and not exists (
        select 1 from checkins c
        where c.parent_id = t.parent_id and c.local_date >= r.local_date
      )
      and not exists (
        select 1 from escalations e
        where e.parent_id = t.parent_id and e.local_date = r.local_date
      )
    order by t.parent_id, r.local_date desc
  ),

  due_morning as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.display_name, t.address_form, t.checkin_time,
           t.window_min, t.timezone, t.child_display_name, t.lang, t.local_date
    from today t
    where t.telegram_user_id is not null
      and (t.paused_until is null or t.paused_until < t.local_date)
      and t.at >= t.checkin_at
      and t.at <  t.checkin_at + make_interval(mins => t.window_min)
      and not exists (
        select 1 from checkins c
        where c.parent_id = t.parent_id and c.local_date = t.local_date
      )
      and not exists (
        select 1 from daily_runs r
        where r.parent_id = t.parent_id
          and r.local_date = t.local_date
          and r.morning_sent_at is not null
      )
  ),

  due_reping as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.display_name, t.address_form, t.checkin_time,
           t.window_min, t.timezone, t.child_display_name, t.lang, r.local_date
    from today t
    join daily_runs r
      on r.parent_id = t.parent_id
     and r.local_date = t.local_date
    where r.morning_sent_at is not null
      and r.delivery_ok
      and r.reping_sent_at is null
      and r.morning_sent_at <= t.at - interval '90 minutes'
      and not exists (
        select 1 from checkins c
        where c.parent_id = t.parent_id and c.local_date = r.local_date
      )
  ),

  due_meds as (
    select t.telegram_user_id, t.family_id,
           m.id    as med_id,
           m.title as med_title,
           s.slot  as slot,
           t.address_form, t.display_name, t.lang,
           false   as is_repeat,
           t.local_date
    from today t
    join meds m on m.parent_id = t.parent_id and m.active
    cross join lateral unnest(m.times) as s(slot)
    cross join lateral (
      select (t.local_date::timestamp + s.slot) at time zone t.timezone as slot_at
    ) k
    where t.telegram_user_id is not null
      and t.local_dow = any(m.days)
      and t.at >= k.slot_at
      and t.at <  k.slot_at + interval '2 hours'
      and (t.at < k.slot_at + interval '90 minutes'
           or (t.local_time >= time '08:00' and t.local_time < time '23:00'))
      and not exists (
        select 1 from med_events e
        where e.med_id = m.id
          and e.local_date = t.local_date
          and e.slot = s.slot
      )
    union all
    select t.telegram_user_id, t.family_id,
           m.id, m.title, e.slot,
           t.address_form, t.display_name, t.lang,
           true,
           e.local_date
    from today t
    join meds m on m.parent_id = t.parent_id
    join med_events e on e.med_id = m.id
    cross join lateral (
      select (e.local_date::timestamp + e.slot) at time zone t.timezone as slot_at
    ) k
    where t.telegram_user_id is not null
      and e.status = 'postponed'
      and e.remind_count < 3
      and e.local_date between t.local_date - 1 and t.local_date
      and t.at >= e.last_reminded_at + interval '30 minutes'
      and t.at <  e.last_reminded_at + interval '2 hours'
      and (t.at < k.slot_at + interval '90 minutes'
           or (t.local_time >= time '08:00' and t.local_time < time '23:00'))
  ),

  due_postcards as (
    select c.id as postcard_id, c.family_id, t.telegram_user_id,
           c.author_name, c.body, c.photo_path, t.lang, c.created_at
    from postcards c
    join today t on t.parent_id = c.parent_id
    where c.sent_at is null
      and t.telegram_user_id is not null
      and t.local_time >= time '08:00'
      and t.local_time <  time '23:00'
    order by c.created_at
    limit 20
  ),

  due_evening as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.address_form, t.display_name, t.lang, t.local_date
    from today t
    where t.telegram_user_id is not null
      and t.evening_at is not null
      and t.at >= t.evening_at
      and t.at <  t.evening_at + interval '2 hours'
      and (t.at < t.evening_at + interval '10 minutes'
           or t.local_time < time '23:00')
      and not exists (
        select 1 from daily_runs r
        where r.parent_id = t.parent_id
          and r.local_date = t.local_date
          and r.evening_sent_at is not null
      )
  ),

  due_story as (
    select t.parent_id, t.family_id, t.telegram_user_id,
           t.address_form, t.display_name, t.lang, t.week_start
    from today t
    where t.telegram_user_id is not null
      and t.created_at < t.at - interval '7 days'
      and t.local_dow = 6
      and t.local_time >= time '12:00'
      and t.local_time <  time '22:00'
      and not exists (
        select 1 from family_stories s
        where s.parent_id = t.parent_id and s.week_start = t.week_start
      )
  ),

  due_digest as (
    select t.parent_id, t.telegram_user_id, t.address_form, t.display_name,
           t.child_display_name, t.lang,
           (select count(*)::int from checkins c
             where c.parent_id = t.parent_id
               and c.local_date between t.week_start and t.local_date
               and c.status in ('ok', 'accidental_ok'))            as ok_days,
           (t.local_date - greatest(t.week_start, t.started_on) + 1)::int as covered_days,
           t.week_start
    from today t
    where t.telegram_user_id is not null
      and t.local_dow = 7
      and t.local_time >= time '19:00'
      and t.local_time <  time '23:00'
      and not exists (
        select 1 from parent_digests pd
        where pd.parent_id = t.parent_id and pd.week_start = t.week_start
      )
      and t.local_date - greatest(t.week_start, t.started_on) + 1 >= 3
  )

  select jsonb_build_object(
    'at', iso_utc(s.at),

    'deadline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          d.parent_id,
        'family_id',          d.family_id,
        'telegram_user_id',   d.telegram_user_id,
        'display_name',       d.display_name,
        'address_form',       d.address_form,
        'checkin_time',       d.checkin_time,
        'window_min',         d.window_min,
        'tz',                 d.timezone,
        'child_display_name', d.child_display_name,
        'lang',               d.lang,
        'local_date',         d.local_date
      )) from due_deadline d
    ), '[]'::jsonb),

    'morning', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          m.parent_id,
        'family_id',          m.family_id,
        'telegram_user_id',   m.telegram_user_id,
        'display_name',       m.display_name,
        'address_form',       m.address_form,
        'checkin_time',       m.checkin_time,
        'window_min',         m.window_min,
        'tz',                 m.timezone,
        'child_display_name', m.child_display_name,
        'lang',               m.lang,
        'local_date',         m.local_date
      )) from due_morning m
    ), '[]'::jsonb),

    'reping', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          r.parent_id,
        'family_id',          r.family_id,
        'telegram_user_id',   r.telegram_user_id,
        'display_name',       r.display_name,
        'address_form',       r.address_form,
        'checkin_time',       r.checkin_time,
        'window_min',         r.window_min,
        'tz',                 r.timezone,
        'child_display_name', r.child_display_name,
        'lang',               r.lang,
        'local_date',         r.local_date
      )) from due_reping r
    ), '[]'::jsonb),

    'meds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'telegram_user_id', x.telegram_user_id,
        'family_id',        x.family_id,
        'med_id',           x.med_id,
        'med_title',        x.med_title,
        'slot',             x.slot,
        'address_form',     x.address_form,
        'display_name',     x.display_name,
        'lang',             x.lang,
        'is_repeat',        x.is_repeat,
        'local_date',       x.local_date
      )) from due_meds x
    ), '[]'::jsonb),

    'postcards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'postcard_id',      c.postcard_id,
        'family_id',        c.family_id,
        'telegram_user_id', c.telegram_user_id,
        'author_name',      c.author_name,
        'body',             c.body,
        'photo_path',       c.photo_path,
        'lang',             c.lang
      ) order by c.created_at) from due_postcards c
    ), '[]'::jsonb),

    'evening', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',        e.parent_id,
        'family_id',        e.family_id,
        'telegram_user_id', e.telegram_user_id,
        'address_form',     e.address_form,
        'display_name',     e.display_name,
        'lang',             e.lang,
        'local_date',       e.local_date
      )) from due_evening e
    ), '[]'::jsonb),

    'story', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',        y.parent_id,
        'family_id',        y.family_id,
        'telegram_user_id', y.telegram_user_id,
        'address_form',     y.address_form,
        'display_name',     y.display_name,
        'lang',             y.lang,
        'week_start',       y.week_start
      )) from due_story y
    ), '[]'::jsonb),

    'digest', coalesce((
      select jsonb_agg(jsonb_build_object(
        'parent_id',          g.parent_id,
        'telegram_user_id',   g.telegram_user_id,
        'address_form',       g.address_form,
        'display_name',       g.display_name,
        'child_display_name', g.child_display_name,
        'lang',               g.lang,
        'ok_days',            g.ok_days,
        'covered_days',       g.covered_days,
        'week_start',         g.week_start
      )) from due_digest g
    ), '[]'::jsonb)
  )
  from snap s;
$$;

revoke all on function cron_due() from public, anon, authenticated;

create or replace function admin_stats()
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'stats', jsonb_build_object(
      'families',        (select count(*) from families),
      'parents_active',  (select count(*) from parents where bot_state = 'active'),
      'waitlist',        (select count(*) from waitlist),
      'stories',         (select count(*) from family_stories where answered_at is not null),
      'postcards',       (select count(*) from postcards where sent_at is not null),
      'checkins_today',  (select count(*) from checkins c join parents p on p.id = c.parent_id
                          where c.local_date = (now() at time zone p.timezone)::date),
      'checkins_7d',     (select count(*) from checkins where local_date > current_date - 7),
      'errors_24h',      (select count(*) from bot_events where at > now() - interval '24 hours')
    ),
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'date', to_char(d, 'DD.MM'),
        'ok',      (select count(*) from checkins c
                    where c.local_date = d::date and c.status in ('ok','accidental_ok')),
        'not_ok',  (select count(*) from checkins c
                    where c.local_date = d::date and c.status = 'not_ok')
      ) order by d), '[]'::jsonb)
      from generate_series(current_date - 13, current_date, '1 day') as d
    ),
    'attention', (
      select coalesce(jsonb_agg(a.item order by a.ord), '[]'::jsonb)
      from (
        select 1 as ord, jsonb_build_object(
          'kind', 'undelivered',
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1)
        ) as item
        from daily_runs r
        join parents p on p.id = r.parent_id
        where r.local_date = (now() at time zone p.timezone)::date
          and not r.delivery_ok

        union all

        select 2, jsonb_build_object(
          'kind', p.bot_state,
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1)
        )
        from parents p
        where p.bot_state in ('blocked', 'stopped')

        union all

        select 3, jsonb_build_object(
          'kind', 'silent',
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1),
          'days', (now() at time zone p.timezone)::date
                  - (select max(c.local_date) from checkins c where c.parent_id = p.id)
        )
        from parents p
        where p.bot_state = 'active'
          and p.telegram_user_id is not null
          and (select max(c.local_date) from checkins c where c.parent_id = p.id)
              < (now() at time zone p.timezone)::date - 2

        union all

        select 4, jsonb_build_object(
          'kind', 'unlinked',
          'parent', p.display_name,
          'child', (select m.display_name from family_members m
                    where m.family_id = p.family_id and m.role = 'owner' limit 1)
        )
        from parents p
        where p.telegram_user_id is null
          and p.created_at < now() - interval '3 days'
      ) a
    ),
    'events', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'at', to_char(e.at, 'DD.MM HH24:MI'),
        'level', e.level,
        'kind', e.kind,
        'detail', left(e.detail, 300)
      ) order by e.at desc), '[]'::jsonb)
      from (select * from bot_events order by at desc limit 30) e
    ),
    'families', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id,
        'created_at', to_char(f.created_at, 'YYYY-MM-DD'),
        'child', (select m.display_name from family_members m
                  where m.family_id = f.id and m.role = 'owner' limit 1),
        'members', (select count(*) from family_members m where m.family_id = f.id),
        'stories', (select count(*) from family_stories s
                    where s.family_id = f.id and s.answered_at is not null),
        'parents', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'display_name', p.display_name,
            'city', p.city,
            'lang', p.lang,
            'bot_state', p.bot_state,
            'checkin_time', to_char(p.checkin_time, 'HH24:MI'),
            'evening_time', to_char(p.evening_time, 'HH24:MI'),
            'last_date', (select to_char(c.local_date, 'DD.MM') from checkins c
                          where c.parent_id = p.id order by c.local_date desc limit 1),
            'last_status', (select c.status from checkins c
                            where c.parent_id = p.id order by c.local_date desc limit 1),
            'streak', (
              select count(*) from (
                select c.local_date, row_number() over (order by c.local_date desc) as rn
                from checkins c
                where c.parent_id = p.id and c.status in ('ok','accidental_ok')
              ) t
              where t.local_date = (select max(c2.local_date) from checkins c2
                                    where c2.parent_id = p.id
                                      and c2.status in ('ok','accidental_ok')) - (t.rn - 1)::int
            )
          ) order by p.created_at), '[]'::jsonb)
          from parents p where p.family_id = f.id
        )
      ) order by f.created_at), '[]'::jsonb)
      from families f
    ),
    'waitlist', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'telegram_user_id', w.telegram_user_id,
        'first_name', w.first_name,
        'username', w.username,
        'lang', w.lang,
        'created_at', to_char(w.created_at, 'YYYY-MM-DD'),
        'invited_at', to_char(w.invited_at, 'DD.MM.YYYY')
      ) order by w.created_at desc), '[]'::jsonb)
      from waitlist w
    )
  );
$$;

revoke all on function admin_stats() from public, anon, authenticated;
