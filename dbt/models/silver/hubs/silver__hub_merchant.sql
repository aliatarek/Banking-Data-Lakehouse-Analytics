{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        merchant_id,
        _source
    from {{ ref('bronze__merchants') }}

),

hashed as (

    select
        {{ hash_key('merchant_id') }} as hk_merchant,
        merchant_id,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        hk_merchant,
        merchant_id,
        load_dts,
        rec_src,
        row_number() over (partition by hk_merchant order by load_dts) as rn
    from hashed

)

select
    hk_merchant,
    merchant_id,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and hk_merchant not in (select hk_merchant from {{ this }})
{% endif %}
