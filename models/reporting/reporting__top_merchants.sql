with current_merchants as (

    select
        hk_merchant as merchant_hub_key,
        merchant_id,
        merchant_name,
        city
    from {{ ref('gold__dim_merchant') }}

)

select
    cm.merchant_hub_key,
    cm.merchant_id,
    cm.merchant_name,
    cm.city,
    count(*) as transaction_count,
    coalesce(sum(ft.amount_usd), 0) as total_transaction_volume_usd,
    rank() over (order by coalesce(sum(ft.amount_usd), 0) desc, cm.merchant_id) as volume_rank
from {{ ref('gold__fact_transactions') }} ft
inner join current_merchants cm on cm.merchant_hub_key = ft.merchant_hub_key
group by 1, 2, 3, 4
