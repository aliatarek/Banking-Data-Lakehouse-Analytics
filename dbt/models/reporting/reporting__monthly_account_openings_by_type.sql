select
    date_trunc('month', open_date)::date as open_month,
    account_type,
    count(*) as new_accounts
from {{ ref('gold__dim_account') }}
group by 1, 2
