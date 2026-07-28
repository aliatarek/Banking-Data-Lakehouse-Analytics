{{ config(materialized='table') }}

with sat as (

    select
        hk_account,
        account_type,
        open_date,
        load_dts,
        rec_src
    from {{ ref('silver__sat_account') }}

),

hub as (

    select
        hk_account,
        account_id
    from {{ ref('silver__hub_account') }}

),

link as (

    select
        hk_account,
        hk_customer
    from {{ ref('silver__link_customer_account') }}

),

versioned as (

    select
        s.hk_account,
        h.account_id,
        l.hk_customer,
        s.account_type,
        s.open_date,
        s.load_dts,
        s.rec_src,
        lead(s.load_dts) over (partition by s.hk_account order by s.load_dts) as next_load_dts
    from sat s
    inner join hub h on h.hk_account = s.hk_account
    inner join link l on l.hk_account = s.hk_account

)

select
    {{ surrogate_key(['hk_account', 'load_dts']) }} as account_key,
    hk_account as account_hub_key,
    account_id,
    hk_customer as customer_hub_key,
    account_type,
    open_date,
    load_dts as effective_start_date,
    coalesce(next_load_dts, '9999-12-31'::timestamp) as effective_end_date,
    (next_load_dts is null) as is_current,
    rec_src as record_source
from versioned
