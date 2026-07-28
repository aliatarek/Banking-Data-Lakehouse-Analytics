with current_accounts as (

    select
        hk_account as account_hub_key,
        account_type,
        open_date
    from {{ ref('gold__dim_account') }}

)

select
    date_trunc('month', ca.open_date)::date as open_month,
    ca.account_type,
    count(*) as account_count,
    coalesce(sum(fab.balance_usd), 0) as total_balance_usd,
    coalesce(avg(fab.balance_usd), 0) as avg_balance_usd
from {{ ref('gold__fact_account_balance') }} fab
inner join current_accounts ca on ca.account_hub_key = fab.account_hub_key
group by 1, 2
