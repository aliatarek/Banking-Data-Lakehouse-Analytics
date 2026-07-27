{{ config(severity='warn') }}

with latest_transaction as (

    select *
    from (
        select
            *,
            row_number() over (partition by hk_transaction order by load_dts desc) as rn
        from {{ ref('silver__sat_transaction') }}
    ) ranked
    where rn = 1

),

latest_account as (

    select *
    from (
        select
            *,
            row_number() over (partition by hk_account order by load_dts desc) as rn
        from {{ ref('silver__sat_account') }}
    ) ranked
    where rn = 1

)

select
    t.hk_transaction,
    t.transaction_date,
    a.hk_account,
    a.open_date as account_open_date
from latest_transaction t
inner join {{ ref('silver__link_account_transaction') }} l on l.hk_transaction = t.hk_transaction
inner join latest_account a on a.hk_account = l.hk_account
where t.transaction_date < a.open_date
