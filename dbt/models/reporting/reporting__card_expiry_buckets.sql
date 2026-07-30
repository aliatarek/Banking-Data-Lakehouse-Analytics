with current_cards as (

    select
        card_id,
        expiration_date::date as expiration_date
    from {{ ref('gold__dim_card') }}
    where is_current

),

bucket_definitions as (

    select 30 as bucket_days
    union all
    select 60 as bucket_days
    union all
    select 90 as bucket_days

)

select
    bd.bucket_days,
    concat('<= ', bd.bucket_days, ' days') as bucket_label,
    count(cc.card_id) as cards_expiring_count,
    current_date as snapshot_date
from bucket_definitions bd
left join current_cards cc
    on cc.expiration_date <= current_date + make_interval(days => bd.bucket_days)
group by 1, 2, 4
