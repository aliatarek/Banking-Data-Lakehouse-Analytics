with current_accounts as (

    select
        hk_account as account_hub_key,
        account_type
    from {{ ref('gold__dim_account') }}

)

select
    ca.account_type,
    count(*) as transaction_count,
    coalesce(sum(ft.amount_usd), 0) as total_transaction_volume_usd,
    coalesce(avg(ft.amount_usd), 0) as avg_transaction_amount_usd
from {{ ref('gold__fact_transactions') }} ft
inner join current_accounts ca on ca.account_hub_key = ft.account_hub_key
group by 1
