{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        merchant_id,
        merchant_name,
        city,
        _source
    from {{ ref('bronze__merchants') }}

),

cleaned as (

    select
        merchant_id,
        trim(merchant_name) as merchant_name,
        initcap(trim(city)) as city,
        _source
    from source_data

),

hashed as (

    select
        {{ hash_key('merchant_id') }} as hk_merchant,
        merchant_name,
        city,
        {{ hash_diff(['merchant_name', 'city']) }} as hash_diff,
        (
            merchant_name is not null and merchant_name <> ''
        ) as _is_valid,
        current_timestamp as load_dts,
        _source as rec_src
    from cleaned

),

deduped as (

    select
        *,
        row_number() over (partition by hk_merchant, hash_diff order by load_dts) as rn
    from hashed

),

latest_existing as (

    {% if is_incremental() %}
    select distinct on (hk_merchant)
        hk_merchant,
        hash_diff as existing_hash_diff
    from {{ this }}
    order by hk_merchant, load_dts desc
    {% else %}
    select
        cast(null as varchar) as hk_merchant,
        cast(null as varchar) as existing_hash_diff
    where false
    {% endif %}

)

select
    d.hk_merchant,
    d.merchant_name,
    d.city,
    d.hash_diff,
    d._is_valid,
    d.load_dts,
    d.rec_src
from deduped d
left join latest_existing le on d.hk_merchant = le.hk_merchant
where d.rn = 1
  and (le.existing_hash_diff is null or le.existing_hash_diff <> d.hash_diff)
