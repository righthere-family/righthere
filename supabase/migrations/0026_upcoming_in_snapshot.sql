create or replace function app_snapshot(p_app_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_family families%rowtype;
  v_parent parents%rowtype;
  v_cards  jsonb := '[]'::jsonb;
  v_first  parents%rowtype;
  v_upcoming jsonb;
begin
  select * into v_family from families where app_token = p_app_token;
  if not found then return null; end if;

  for v_parent in
    select * from parents where family_id = v_family.id order by created_at
  loop
    if v_first.id is null then v_first := v_parent; end if;
    v_cards := v_cards || jsonb_build_array(app_parent_card(v_parent));
  end loop;

  if jsonb_array_length(v_cards) = 0 then return null; end if;

  v_upcoming := app_upcoming_date(
    v_family.id,
    (now() at time zone v_first.timezone)::date
  );

  return (v_cards -> 0)
    || jsonb_build_object('parents', v_cards)
    || coalesce(jsonb_build_object('upcoming_date', v_upcoming), '{}'::jsonb);
end $$;
