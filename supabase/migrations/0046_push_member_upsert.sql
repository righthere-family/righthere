drop function if exists app_set_push_token(uuid, text, text, text, text);

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

  insert into family_members (family_id, user_id, role, display_name, timezone, apns_token, apns_env, push_lang)
  values (v_family_id, auth.uid(), 'sibling', '',
          coalesce(nullif(p_timezone, ''), 'UTC'), p_token, p_env, p_lang)
  on conflict (family_id, user_id) do update
     set apns_token = excluded.apns_token,
         apns_env   = excluded.apns_env,
         push_lang  = excluded.push_lang,
         timezone   = coalesce(nullif(p_timezone, ''), family_members.timezone);
  return true;
end $$;

revoke all on function app_set_push_token(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function app_set_push_token(uuid, text, text, text, text)
  to anon, authenticated;
