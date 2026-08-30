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
        'display_name', m.display_name, 'role', m.role
      )), '[]'::jsonb)
      from family_members m where m.family_id = f.id
    ),
    'parents', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'display_name', p.display_name,
        'address_form', p.address_form,
        'city', p.city,
        'timezone', p.timezone,
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

revoke all on function admin_family(uuid) from public, anon, authenticated;
