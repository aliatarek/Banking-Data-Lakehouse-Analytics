select
    date_trunc('year', open_date)::date as open_year,
    account_type,
    count(*) as new_accounts
from {{ ref('gold__dim_account') }}
where is_current
group by 1, 2
