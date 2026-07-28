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
    count(*) as loan_count,
    coalesce(sum(fl.loan_amount), 0) as total_loan_amount_usd,
    coalesce(avg(fl.interest_rate), 0) as avg_interest_rate
from {{ ref('gold__fact_loans') }} fl
inner join current_customers cc on cc.customer_hub_key = fl.hk_customer
group by 1, 2
