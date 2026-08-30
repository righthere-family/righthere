create table if not exists family_stories (
  id            uuid primary key default gen_random_uuid(),
  family_id     uuid not null references families(id) on delete cascade,
  parent_id     uuid not null references parents(id) on delete cascade,
  question      text not null,
  asked_at      timestamptz not null default now(),
  week_start    date not null,
  answer_text   text,
  voice_file_id text,
  answered_at   timestamptz,
  unique (parent_id, week_start)
);

alter table family_stories enable row level security;

create policy stories_read on family_stories for select
  using (is_family_member(family_id));

create or replace function parents_due_for_story()
returns table (
  parent_id        uuid,
  family_id        uuid,
  telegram_user_id bigint,
  address_form     text,
  display_name     text,
  week_start       date
)
language sql stable as $$
  select p.id, p.family_id, p.telegram_user_id,
         p.address_form, p.display_name,
         date_trunc('week', (now() at time zone p.timezone))::date
  from parents p
  where p.bot_state = 'active'
    and p.telegram_user_id is not null
    and p.created_at < now() - interval '7 days'
    and extract(isodow from (now() at time zone p.timezone))::int = 6
    and (now() at time zone p.timezone)::time >= time '12:00'
    and (now() at time zone p.timezone)::time <  time '12:10'
    and not exists (
      select 1 from family_stories s
      where s.parent_id = p.id
        and s.week_start = date_trunc('week', (now() at time zone p.timezone))::date
    );
$$;

create or replace function story_asked(
  p_parent_id uuid,
  p_family_id uuid,
  p_question text,
  p_week_start date
)
returns void
language sql as $$
  insert into family_stories (family_id, parent_id, question, week_start)
  values (p_family_id, p_parent_id, p_question, p_week_start)
  on conflict (parent_id, week_start) do nothing;
$$;

create or replace function story_capture(
  p_telegram_user_id bigint,
  p_text text,
  p_voice_file_id text
)
returns uuid
language plpgsql as $$
declare
  v_parent parents%rowtype;
  v_story  family_stories%rowtype;
begin
  select * into v_parent from parents where telegram_user_id = p_telegram_user_id;
  if not found then return null; end if;

  select * into v_story
  from family_stories
  where parent_id = v_parent.id
    and answered_at is null
    and asked_at > now() - interval '24 hours'
  order by asked_at desc
  limit 1;
  if not found then return null; end if;

  if p_voice_file_id is null and length(trim(coalesce(p_text, ''))) < 50 then
    return null;
  end if;

  update family_stories
     set answer_text = nullif(trim(coalesce(p_text, '')), ''),
         voice_file_id = p_voice_file_id,
         answered_at = now()
   where id = v_story.id;
  return v_parent.family_id;
end $$;

create or replace function app_stories(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  return coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', s.id,
      'parent_id', s.parent_id,
      'question', s.question,
      'answer_text', s.answer_text,
      'voice_file_id', s.voice_file_id,
      'answered_at', iso_utc(s.answered_at)
    )) order by s.answered_at desc)
    from family_stories s
    where s.family_id = v_family.id and s.answered_at is not null
  ), '[]'::jsonb);
end $$;

create table if not exists family_dates (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references families(id) on delete cascade,
  title      text not null,
  month      int not null check (month between 1 and 12),
  day        int not null check (day between 1 and 31),
  created_at timestamptz not null default now()
);

alter table family_dates enable row level security;

create policy dates_read on family_dates for select
  using (is_family_member(family_id));

create or replace function app_dates(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'title', d.title, 'month', d.month, 'day', d.day
    ) order by d.month, d.day)
    from family_dates d where d.family_id = v_family.id
  ), '[]'::jsonb);
end $$;

create or replace function app_date_add(
  p_app_token uuid,
  p_title text,
  p_month int,
  p_day int
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_id uuid;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;
  if nullif(trim(p_title), '') is null then return null; end if;
  if (select count(*) from family_dates where family_id = v_family.id) >= 20 then
    return null;
  end if;
  insert into family_dates (family_id, title, month, day)
  values (v_family.id, trim(p_title), p_month, p_day)
  returning id into v_id;
  return v_id;
end $$;

create or replace function app_date_delete(p_app_token uuid, p_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;
  delete from family_dates where id = p_id and family_id = v_family.id;
  return found;
end $$;

create or replace function app_upcoming_date(p_family_id uuid, p_today date)
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'title', d.title,
    'days_left', (make_date(extract(year from p_today)::int, d.month, d.day)
                  + case when make_date(extract(year from p_today)::int, d.month, d.day) < p_today
                         then interval '1 year' else interval '0' end)::date - p_today
  )
  from family_dates d
  where d.family_id = p_family_id
    and (make_date(extract(year from p_today)::int, d.month, d.day)
         + case when make_date(extract(year from p_today)::int, d.month, d.day) < p_today
                then interval '1 year' else interval '0' end)::date - p_today <= 7
  order by (make_date(extract(year from p_today)::int, d.month, d.day)
            + case when make_date(extract(year from p_today)::int, d.month, d.day) < p_today
                   then interval '1 year' else interval '0' end)::date - p_today
  limit 1;
$$;

create or replace function app_set_window(
  p_app_token uuid,
  p_parent_id uuid,
  p_minutes int
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  if p_minutes not between 60 and 360 then return false; end if;
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return false; end if;
  update parents set window_min = p_minutes where id = v_parent.id;
  return true;
end $$;

revoke all on function parents_due_for_story()                    from public, anon, authenticated;
revoke all on function story_asked(uuid, uuid, text, date)        from public, anon, authenticated;
revoke all on function story_capture(bigint, text, text)          from public, anon, authenticated;
revoke all on function app_stories(uuid)                          from public, anon, authenticated;
revoke all on function app_dates(uuid)                            from public, anon, authenticated;
revoke all on function app_date_add(uuid, text, int, int)         from public, anon, authenticated;
revoke all on function app_date_delete(uuid, uuid)                from public, anon, authenticated;
revoke all on function app_upcoming_date(uuid, date)              from public, anon, authenticated;
revoke all on function app_set_window(uuid, uuid, int)            from public, anon, authenticated;
grant execute on function app_stories(uuid)                       to anon, authenticated;
grant execute on function app_dates(uuid)                         to anon, authenticated;
grant execute on function app_date_add(uuid, text, int, int)      to anon, authenticated;
grant execute on function app_date_delete(uuid, uuid)             to anon, authenticated;
grant execute on function app_set_window(uuid, uuid, int)         to anon, authenticated;
