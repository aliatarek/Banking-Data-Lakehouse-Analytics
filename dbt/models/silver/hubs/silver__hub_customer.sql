{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        customer_id,
        _source
    from {{ ref('bronze__customers') }}

),

hashed as (

    select
        {{ hash_key('customer_id') }} as hk_customer,
        customer_id,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        hk_customer,
        customer_id,
        load_dts,
        rec_src,
        row_number() over (partition by hk_customer order by load_dts) as rn
    from hashed

)

select
    hk_customer,
    customer_id,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and not exists (
    select 1 from {{ this }} existing
    where existing.hk_customer = deduped.hk_customer
  )
{% endif %}
