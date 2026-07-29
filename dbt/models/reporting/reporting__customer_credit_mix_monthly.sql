with monthly_counts as (

    select
        acquisition_month,
        credit_tier,
        count(*) as customer_count
    from {{ ref('gold__dim_customer') }}
    where is_current
    group by 1, 2

)

select
    acquisition_month,
    credit_tier,
    case credit_tier
        when 'deep_subprime' then 1
        when 'subprime' then 2
        when 'near_prime' then 3
        when 'prime' then 4
        when 'super_prime' then 5
        else 99
    end as credit_tier_sort_order,
    customer_count,
    round(
        customer_count::numeric
        / nullif(sum(customer_count) over (partition by acquisition_month), 0)::numeric * 100,
        2
    ) as pct_of_month_total
from monthly_counts
