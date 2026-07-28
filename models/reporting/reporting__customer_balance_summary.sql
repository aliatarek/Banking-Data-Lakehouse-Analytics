with current_customers as (

    select
        hk_customer as customer_hub_key,
        customer_id,
        first_name,
        last_name,
        city,
        case
            when credit_score is null then null
            when credit_score >= 800 then 'excellent'
            when credit_score >= 740 then 'good'
            when credit_score >= 670 then 'fair'
            when credit_score >= 580 then 'poor'
            else 'very_poor'
        end as credit_tier
    from {{ ref('gold__dim_customer') }}

),

customer_balances as (

    select
        customer_hub_key,
        sum(balance_usd) as total_balance_usd,
        count(*) as account_count
    from {{ ref('gold__fact_account_balance') }}
    group by 1

)

select
    cc.customer_hub_key,
    cc.customer_id,
    cc.first_name,
    cc.last_name,
    cc.city,
    cc.credit_tier,
    coalesce(cb.account_count, 0) as account_count,
    coalesce(cb.total_balance_usd, 0) as total_balance_usd,
    rank() over (order by coalesce(cb.total_balance_usd, 0) desc, cc.customer_id) as balance_rank
from current_customers cc
left join customer_balances cb on cb.customer_hub_key = cc.customer_hub_key
