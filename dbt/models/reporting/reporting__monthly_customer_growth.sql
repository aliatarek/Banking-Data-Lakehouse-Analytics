select
    date_trunc('month', created_at)::date as acquisition_month,
    count(*) as new_customers
from {{ ref('gold__dim_customer') }}
group by 1
