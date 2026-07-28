{{ config(materialized='table') }}

with date_spine as (

    select generate_series(
        '2015-01-01'::date,
        '2030-01-02'::date,
        interval '1 day'
    )::date as date_day

),

date_spine_bounded as (

    select date_day
    from date_spine
    where date_day <= '2030-01-01'::date

)

select
    to_char(date_day, 'YYYYMMDD')::int as date_key,
    date_day,
    extract(year from date_day)::int as year,
    extract(quarter from date_day)::int as quarter,
    extract(month from date_day)::int as month,
    trim(to_char(date_day, 'Month')) as month_name,
    extract(day from date_day)::int as day_of_month,
    extract(isodow from date_day)::int as day_of_week,
    trim(to_char(date_day, 'Day')) as day_name,
    (extract(isodow from date_day) in (6, 7)) as is_weekend,
    extract(week from date_day)::int as week_of_year,
    extract(doy from date_day)::int as day_of_year,
    (date_day = (date_trunc('month', date_day) + interval '1 month' - interval '1 day')::date) as is_month_end
from date_spine_bounded
