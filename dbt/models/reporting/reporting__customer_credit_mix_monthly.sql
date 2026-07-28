with monthly_counts as (

    select
        date_trunc('month', created_at)::date as acquisition_month,
        case
            when credit_score is null then null
            when credit_score >= 800 then 'excellent'
            when credit_score >= 740 then 'good'
            when credit_score >= 670 then 'fair'
            when credit_score >= 580 then 'poor'
            else 'very_poor'
        end as credit_tier,
        count(*) as customer_count
    from {{ ref('gold__dim_customer') }}
    group by 1, 2

)

select
    acquisition_month,
    credit_tier,
    case credit_tier
        when 'very_poor' then 1
        when 'poor' then 2
        when 'fair' then 3
        when 'good' then 4
        when 'excellent' then 5
        else 99
    end as credit_tier_sort_order,
    customer_count,
    round(
        customer_count::numeric
        / nullif(sum(customer_count) over (partition by acquisition_month), 0)::numeric * 100,
        2
    ) as pct_of_month_total
from monthly_counts
