{{ config(materialized='table') }}

with sat as (

    select
        hk_transaction,
        amount_usd,
        transaction_date,
        load_dts,
        rec_src
    from {{ ref('silver__sat_transaction') }}

),

link_account_transaction as (

    select
        hk_transaction,
        hk_account
    from {{ ref('silver__link_account_transaction') }}

),

link_merchant_transaction as (

    select
        hk_transaction,
        hk_merchant
    from {{ ref('silver__link_merchant_transaction') }}

),

link_customer_account as (

    select
        hk_account,
        hk_customer
    from {{ ref('silver__link_customer_account') }}

)

select
    s.hk_transaction as transaction_hub_key,
    lat.hk_account as account_hub_key,
    lmt.hk_merchant as merchant_hub_key,
    lca.hk_customer as customer_hub_key,
    to_char(s.transaction_date, 'YYYYMMDD')::int as date_key,
    s.transaction_date,
    s.amount_usd,
    s.rec_src as record_source,
    s.load_dts as load_date
from sat s
inner join link_account_transaction lat on lat.hk_transaction = s.hk_transaction
inner join link_merchant_transaction lmt on lmt.hk_transaction = s.hk_transaction
inner join link_customer_account lca on lca.hk_account = lat.hk_account
