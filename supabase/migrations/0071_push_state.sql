alter table family_members
  add column if not exists push_state text not null default 'unknown'
    check (push_state in ('unknown', 'granted', 'denied', 'gone')),
  add column if not exists push_seen_at timestamptz;

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
  if auth.uid() is null then
    return false;
  end if;
  select id into v_family_id from families where app_token = p_app_token;
  if not found then
    return false;
  end if;

  insert into family_members (family_id, user_id, role, display_name, timezone,
                              apns_token, apns_env, push_lang, push_state, push_seen_at)
  values (v_family_id, auth.uid(), 'sibling', '',
          coalesce(nullif(p_timezone, ''), 'UTC'), p_token, p_env, p_lang, 'granted', now())
  on conflict (family_id, user_id) do update
     set apns_token   = excluded.apns_token,
         apns_env     = excluded.apns_env,
         push_lang    = excluded.push_lang,
         push_state   = 'granted',
         push_seen_at = now(),
         timezone     = coalesce(nullif(p_timezone, ''), family_members.timezone);
  return true;
end $$;

create or replace function app_set_push_denied(p_app_token uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family_id uuid;
begin
  if auth.uid() is null then
    return false;
  end if;
  select id into v_family_id from families where app_token = p_app_token;
  if not found then
    return false;
  end if;
  update family_members
     set apns_token   = null,
         push_state   = 'denied',
         push_seen_at = now()
   where family_id = v_family_id and user_id = auth.uid();
  return found;
end $$;

revoke all on function app_set_push_denied(uuid) from public, anon, authenticated;
grant execute on function app_set_push_denied(uuid) to anon, authenticated;

create or replace function admin_family(p_family_id uuid)
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'id', f.id,
    'app_token', f.app_token,
    'created_at', to_char(f.created_at, 'YYYY-MM-DD'),
    'subscription', (
      select jsonb_build_object('entitlement', s.entitlement, 'status', s.status,
                                'source', s.rc_app_user_id)
      from subscriptions s where s.family_id = f.id
    ),
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'display_name', m.display_name,
        'role', m.role,
        'timezone', m.timezone,
        'has_token', m.apns_token is not null,
        'push_state', m.push_state,
        'push_seen', to_char(m.push_seen_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI')
      ) order by m.created_at), '[]'::jsonb)
      from family_members m where m.family_id = f.id
    ),
    'parents', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'display_name', p.display_name,
        'address_form', p.address_form,
        'city', p.city,
        'timezone', p.timezone,
        'lang', p.lang,
        'bot_state', p.bot_state,
        'paused_until', to_char(p.paused_until, 'YYYY-MM-DD'),
        'checkin_time', to_char(p.checkin_time, 'HH24:MI'),
        'evening_time', to_char(p.evening_time, 'HH24:MI'),
        'window_min', p.window_min,
        'connected', p.telegram_user_id is not null,
        'meds', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'title', m.title,
            'times', (select jsonb_agg(to_char(t, 'HH24:MI') order by t) from unnest(m.times) t)
          )), '[]'::jsonb)
          from meds m where m.parent_id = p.id and m.active
        ),
        'strip', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'd', to_char(d, 'DD'),
            's', coalesce((select c.status from checkins c
                           where c.parent_id = p.id and c.local_date = d::date), 'none')
          ) order by d), '[]'::jsonb)
          from generate_series(current_date - 13, current_date, '1 day') d
        )
      ) order by p.created_at), '[]'::jsonb)
      from parents p where p.family_id = f.id
    ),
    'stories', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'question', s.question,
        'answer', s.answer_text,
        'has_voice', s.voice_file_id is not null,
        'at', to_char(s.answered_at, 'YYYY-MM-DD')
      ) order by s.answered_at desc), '[]'::jsonb)
      from family_stories s where s.family_id = f.id and s.answered_at is not null
    )
  )
  from families f where f.id = p_family_id;
$$;
