{{ config(materialized='table') }}

with latest_sat as (

    select *
    from (
        select
            *,
            row_number() over (partition by hk_account order by load_dts desc) as rn
        from {{ ref('silver__sat_account') }}
    ) ranked
    where rn = 1

),

link as (

    select
        hk_account,
        hk_customer
    from {{ ref('silver__link_customer_account') }}

)

select
    s.hk_account as account_hub_key,
    l.hk_customer as customer_hub_key,
    to_char(s.load_dts::date, 'YYYYMMDD')::int as date_key,
    s.load_dts::date as snapshot_date,
    s.open_date,
    s.balance_usd,
    s.rec_src as record_source,
    s.load_dts as load_date
from latest_sat s
inner join link l on l.hk_account = s.hk_account
