{{ config(materialized='table') }}

with sat as (

    select
        hk_merchant,
        merchant_name,
        city,
        load_dts,
        rec_src
    from {{ ref('silver__sat_merchant') }}

),

hub as (

    select
        hk_merchant,
        merchant_id
    from {{ ref('silver__hub_merchant') }}

),

versioned as (

    select
        s.hk_merchant,
        h.merchant_id,
        s.merchant_name,
        s.city,
        s.load_dts,
        s.rec_src,
        lead(s.load_dts) over (partition by s.hk_merchant order by s.load_dts) as next_load_dts
    from sat s
    inner join hub h on h.hk_merchant = s.hk_merchant

)

select
    {{ surrogate_key(['hk_merchant', 'load_dts']) }} as merchant_key,
    hk_merchant as merchant_hub_key,
    merchant_id,
    merchant_name,
    city,
    load_dts as effective_start_date,
    coalesce(next_load_dts, '9999-12-31'::timestamp) as effective_end_date,
    (next_load_dts is null) as is_current,
    rec_src as record_source
from versioned
