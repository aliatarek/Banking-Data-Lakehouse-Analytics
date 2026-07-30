with current_customers as (

    select
        customer_hub_key,
        credit_tier
    from {{ ref('gold__dim_customer') }}
    where is_current

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
    count(*) as loan_count,
    coalesce(sum(fl.loan_amount), 0) as total_loan_amount_usd,
    coalesce(avg(fl.interest_rate), 0) as avg_interest_rate
from {{ ref('gold__fact_loans') }} fl
inner join current_customers cc on cc.customer_hub_key = fl.customer_hub_key
group by 1, 2
