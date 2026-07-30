{{ config(materialized='table') }}

with customer_quarantine as (

    select
        'customer' as source_table,
        h.customer_id as source_business_key,
        s.hk_customer as hash_key,
        'failed customer validation: email format, credit_score range (300-850), or created_at in the future' as rejection_reason,
        s.load_dts
    from {{ ref('silver__sat_customer') }} s
    inner join {{ ref('silver__hub_customer') }} h on h.hk_customer = s.hk_customer
    where s._is_valid = false

),

account_quarantine as (

    select
        'account' as source_table,
        h.account_id as source_business_key,
        s.hk_account as hash_key,
        'failed account validation: balance_usd negative or account_type not recognized' as rejection_reason,
        s.load_dts
    from {{ ref('silver__sat_account') }} s
    inner join {{ ref('silver__hub_account') }} h on h.hk_account = s.hk_account
    where s._is_valid = false

),

card_quarantine as (

    select
        'card' as source_table,
        h.card_id as source_business_key,
        s.hk_card as hash_key,
        'failed card validation: card_type not recognized' as rejection_reason,
        s.load_dts
    from {{ ref('silver__sat_card') }} s
    inner join {{ ref('silver__hub_card') }} h on h.hk_card = s.hk_card
    where s._is_valid = false

),

merchant_quarantine as (

    select
        'merchant' as source_table,
        h.merchant_id as source_business_key,
        s.hk_merchant as hash_key,
        'failed merchant validation: merchant_name is null or empty' as rejection_reason,
        s.load_dts
    from {{ ref('silver__sat_merchant') }} s
    inner join {{ ref('silver__hub_merchant') }} h on h.hk_merchant = s.hk_merchant
    where s._is_valid = false

),

branch_quarantine as (

    select
        'branch' as source_table,
        h.branch_id as source_business_key,
        s.hk_branch as hash_key,
        'failed branch validation: branch_name is null or empty' as rejection_reason,
        s.load_dts
    from {{ ref('silver__sat_branch') }} s
    inner join {{ ref('silver__hub_branch') }} h on h.hk_branch = s.hk_branch
    where s._is_valid = false

),

loan_quarantine as (

    select
        'loan' as source_table,
        h.loan_id as source_business_key,
        s.hk_loan as hash_key,
        'failed loan validation: loan_amount not positive or interest_rate outside 0-100' as rejection_reason,
        s.load_dts
    from {{ ref('silver__sat_loan') }} s
    inner join {{ ref('silver__hub_loan') }} h on h.hk_loan = s.hk_loan
    where s._is_valid = false

),

transaction_quarantine as (

    select
        'transaction' as source_table,
        h.transaction_id as source_business_key,
        s.hk_transaction as hash_key,
        'failed transaction validation: amount_usd not positive or transaction_date in the future' as rejection_reason,
        s.load_dts
    from {{ ref('silver__sat_transaction') }} s
    inner join {{ ref('silver__hub_transaction') }} h on h.hk_transaction = s.hk_transaction
    where s._is_valid = false

)

select * from customer_quarantine
union all
select * from account_quarantine
union all
select * from card_quarantine
union all
select * from merchant_quarantine
union all
select * from branch_quarantine
union all
select * from loan_quarantine
union all
select * from transaction_quarantine
