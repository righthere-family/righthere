alter table subscriptions add column if not exists original_transaction_id text;
alter table subscriptions add column if not exists product_id text;
alter table subscriptions add column if not exists environment text;
create unique index if not exists subscriptions_original_transaction
  on subscriptions (original_transaction_id) where original_transaction_id is not null;

drop function if exists app_set_subscription(uuid, text, text, timestamptz);

create or replace function server_set_subscription(
  p_app_token uuid,
  p_entitlement text,
  p_product text,
  p_original_transaction_id text,
  p_environment text,
  p_status text,
  p_expires_at timestamptz
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_family families%rowtype;
begin
  if p_entitlement not in ('premium', 'family') or p_status not in ('active', 'expired', 'revoked') then
    return false;
  end if;
  select * into v_family from families where app_token = p_app_token;
  if not found then return false; end if;

  delete from subscriptions
   where original_transaction_id = p_original_transaction_id
     and family_id <> v_family.id;

  insert into subscriptions (family_id, rc_app_user_id, entitlement, status, expires_at, updated_at,
                             original_transaction_id, product_id, environment)
  values (v_family.id, 'apple:' || p_original_transaction_id, p_entitlement, p_status, p_expires_at, now(),
          p_original_transaction_id, p_product, p_environment)
  on conflict (family_id) do update
    set rc_app_user_id          = excluded.rc_app_user_id,
        entitlement             = excluded.entitlement,
        status                  = excluded.status,
        expires_at              = excluded.expires_at,
        updated_at              = now(),
        original_transaction_id = excluded.original_transaction_id,
        product_id              = excluded.product_id,
        environment             = excluded.environment;
  return true;
end $$;

create or replace function server_update_subscription(
  p_original_transaction_id text,
  p_entitlement text,
  p_product text,
  p_environment text,
  p_status text,
  p_expires_at timestamptz
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_entitlement not in ('premium', 'family') or p_status not in ('active', 'expired', 'revoked') then
    return false;
  end if;
  update subscriptions
     set entitlement = p_entitlement,
         product_id  = p_product,
         environment = p_environment,
         status      = p_status,
         expires_at  = p_expires_at,
         updated_at  = now()
   where original_transaction_id = p_original_transaction_id;
  return found;
end $$;

create or replace function family_entitlement(p_app_token uuid)
returns text
language sql stable security definer set search_path = public as $$
  select s.entitlement
  from subscriptions s
  join families f on f.id = s.family_id
  where f.app_token = p_app_token
    and s.status = 'active'
    and (s.expires_at is null or s.expires_at > now() - interval '2 days')
  limit 1;
$$;

create or replace function app_med_add(
  p_app_token uuid,
  p_title text,
  p_times time[],
  p_parent_id uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_med meds%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;
  if nullif(trim(p_title), '') is null or cardinality(p_times) = 0 then
    return null;
  end if;
  if family_entitlement(p_app_token) is null
     and exists (select 1 from meds where parent_id = v_parent.id and active) then
    return null;
  end if;

  insert into meds (parent_id, title, human_text, times)
  values (v_parent.id, trim(p_title), trim(p_title), p_times)
  returning * into v_med;

  return jsonb_build_object('id', v_med.id);
end $$;


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
  if p_minutes <> 180 and family_entitlement(p_app_token) is null then return false; end if;
  update parents set window_min = p_minutes where id = v_parent.id;
  return true;
end $$;


create or replace function app_set_evening_time(
  p_app_token uuid,
  p_parent_id uuid,
  p_time time
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
begin
  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return false; end if;
  if p_time is not null and family_entitlement(p_app_token) is null then return false; end if;
  update parents set evening_time = p_time where id = v_parent.id;
  return true;
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
  if family_entitlement(p_app_token) is null then return null; end if;
  if nullif(trim(p_title), '') is null then return null; end if;
  if (select count(*) from family_dates where family_id = v_family.id) >= 20 then
    return null;
  end if;
  insert into family_dates (family_id, title, month, day)
  values (v_family.id, trim(p_title), p_month, p_day)
  returning id into v_id;
  return v_id;
end $$;


create or replace function app_month(
  p_app_token uuid,
  p_year int,
  p_month int,
  p_parent_id uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_parent parents%rowtype;
  v_today  date;
  v_start  date;
  v_first  date;
  v_days   jsonb;
begin
  if p_month not between 1 and 12 or p_year not between 2020 and 2100 then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;

  v_parent := app_parent_for(p_app_token, p_parent_id);
  if v_parent.id is null then return null; end if;

  v_today := (now() at time zone v_parent.timezone)::date;
  if make_date(p_year, p_month, 1) < date_trunc('month', v_today)::date
     and family_entitlement(p_app_token) is null then
    return jsonb_build_object('today', null, 'days', '[]'::jsonb);
  end if;
  v_start := (v_parent.created_at at time zone v_parent.timezone)::date;
  v_first := make_date(p_year, p_month, 1);

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'day',   extract(day from d)::int,
    'mark',  case
               when d > v_today or d < v_start then 'upcoming'
               when c.status in ('ok', 'accidental_ok') then 'ok'
               when c.status = 'not_ok' then 'not_ok'
               when d = v_today then 'today'
               else 'missed'
             end,
    'time',  case when c.status in ('ok', 'accidental_ok')
                  then to_char(c.created_at at time zone v_parent.timezone, 'HH24:MI') end,
    'quote', case when c.status = 'not_ok' then c.free_text end
  )) order by d), '[]'::jsonb)
  into v_days
  from generate_series(v_first, (v_first + interval '1 month' - interval '1 day')::date, '1 day') as d
  left join checkins c on c.parent_id = v_parent.id and c.local_date = d::date;

  return jsonb_build_object(
    'today', case when date_trunc('month', v_today::timestamp)::date = v_first
                  then extract(day from v_today)::int end,
    'days',  v_days
  );
end;
$$;


revoke all on function server_set_subscription(uuid, text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
revoke all on function server_update_subscription(text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
