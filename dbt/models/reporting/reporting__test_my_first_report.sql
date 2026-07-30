select
    date_trunc('month', created_date)::date as signup_month,
    count(*) as customer_count
from {{ ref('gold__dim_customer') }}
group by 1
