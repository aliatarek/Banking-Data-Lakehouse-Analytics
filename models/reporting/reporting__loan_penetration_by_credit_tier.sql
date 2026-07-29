with current_customers as (

    select
        customer_hub_key,
        credit_tier
    from {{ ref('gold__dim_customer') }}
    where is_current

),

loan_customers as (

    select distinct
        customer_hub_key
    from {{ ref('gold__fact_loans') }}

)

select
    cc.credit_tier,
    case cc.credit_tier
        when 'deep_subprime' then 1
        when 'subprime' then 2
        when 'near_prime' then 3
        when 'prime' then 4
        when 'super_prime' then 5
        else 99
    end as credit_tier_sort_order,
    count(*) as total_customers,
    sum(case when lc.customer_hub_key is not null then 1 else 0 end) as customers_with_loans,
    round(
        sum(case when lc.customer_hub_key is not null then 1 else 0 end)::numeric
        / nullif(count(*), 0)::numeric * 100,
        2
    ) as loan_penetration_pct
from current_customers cc
left join loan_customers lc on lc.customer_hub_key = cc.customer_hub_key
group by 1, 2
