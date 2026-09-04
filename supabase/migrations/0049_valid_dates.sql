update family_dates
   set day = case month
               when 2 then least(day, 29)
               when 4 then least(day, 30)
               when 6 then least(day, 30)
               when 9 then least(day, 30)
               when 11 then least(day, 30)
               else least(day, 31)
             end
 where day > case month
               when 2 then 29
               when 4 then 30
               when 6 then 30
               when 9 then 30
               when 11 then 30
               else 31
             end;

alter table family_dates
  add constraint family_dates_day_fits_month
  check (
    day between 1 and case month
      when 2 then 29
      when 4 then 30
      when 6 then 30
      when 9 then 30
      when 11 then 30
      else 31
    end
  );

create or replace function safe_date(p_year int, p_month int, p_day int)
returns date
language sql immutable as $$
  select make_date(
    p_year,
    p_month,
    least(p_day, extract(day from (make_date(p_year, p_month, 1) + interval '1 month - 1 day'))::int)
  );
$$;

create or replace function app_upcoming_date(p_family_id uuid, p_today date)
returns jsonb
language sql stable as $$
  with dates as (
    select d.title,
           (safe_date(extract(year from p_today)::int, d.month, d.day)
            + case when safe_date(extract(year from p_today)::int, d.month, d.day) < p_today
                   then interval '1 year' else interval '0' end)::date as next_at
    from family_dates d
    where d.family_id = p_family_id
  )
  select jsonb_build_object('title', title, 'days_left', next_at - p_today)
  from dates
  where next_at - p_today <= 7
  order by next_at
  limit 1;
$$;
