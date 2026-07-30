select
    acquisition_month,
    count(*) as new_customers
from {{ ref('gold__dim_customer') }}
where is_current
group by 1
