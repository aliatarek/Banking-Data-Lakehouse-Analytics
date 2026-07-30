with customer_balances as (

    select
        customer_hub_key,
        sum(balance_usd) as total_balance_usd
    from {{ ref('gold__fact_account_balance') }}
    group by 1

)

select
    count(*) as customers_with_balance_rows,
    coalesce(avg(total_balance_usd), 0) as avg_balance_usd,
    coalesce(percentile_cont(0.5) within group (order by total_balance_usd), 0) as median_balance_usd,
    coalesce(sum(total_balance_usd), 0) as total_balance_usd,
    current_date as snapshot_date
from customer_balances
