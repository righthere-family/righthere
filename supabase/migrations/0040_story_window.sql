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
    and asked_at > now() - interval '3 hours'
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
