with current_customers as (

    select
        hk_customer as customer_hub_key
    from {{ ref('gold__dim_customer') }}

),

customer_balances as (

    select
        customer_hub_key,
        sum(balance_usd) as total_balance_usd,
        count(*) as account_count
    from {{ ref('gold__fact_account_balance') }}
    group by 1

),

loan_totals as (

    select
        coalesce(sum(loan_amount), 0) as total_loan_book_usd
    from {{ ref('gold__fact_loans') }}

),

transaction_totals as (

    select
        coalesce(sum(amount_usd), 0) as total_transaction_volume_usd
    from {{ ref('gold__fact_transactions') }}

)

select
    count(*) as total_customers,
    coalesce(sum(cb.account_count), 0) as total_accounts,
    coalesce(sum(cb.total_balance_usd), 0) as total_deposits_usd,
    coalesce(sum(case when cb.account_count > 1 then 1 else 0 end), 0) as customers_with_multiple_accounts,
    case
        when count(*) = 0 then 0
        else round(
            coalesce(sum(case when cb.account_count > 1 then 1 else 0 end), 0)::numeric
            / count(*)::numeric * 100,
            2
        )
    end as pct_customers_with_multiple_accounts,
    max(lt.total_loan_book_usd) as total_loan_book_usd,
    max(tt.total_transaction_volume_usd) as total_transaction_volume_usd,
    current_date as snapshot_date
from current_customers cc
left join customer_balances cb on cb.customer_hub_key = cc.customer_hub_key
cross join loan_totals lt
cross join transaction_totals tt
