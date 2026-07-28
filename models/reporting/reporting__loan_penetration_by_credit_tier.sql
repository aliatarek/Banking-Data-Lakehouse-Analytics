with current_customers as (

    select
        hk_customer as customer_hub_key,
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

loan_customers as (

    select distinct
        hk_customer as customer_hub_key
    from {{ ref('gold__fact_loans') }}

)

select
    cc.credit_tier,
    case cc.credit_tier
        when 'very_poor' then 1
        when 'poor' then 2
        when 'fair' then 3
        when 'good' then 4
        when 'excellent' then 5
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
