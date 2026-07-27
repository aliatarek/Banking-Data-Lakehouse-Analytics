{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        card_id,
        card_type,
        expiration_date,
        _source
    from {{ ref('bronze__cards') }}

),

cleaned as (

    select
        card_id,
        trim(card_type) as card_type,
        expiration_date,
        _source
    from source_data

),

hashed as (

    select
        {{ hash_key('card_id') }} as hk_card,
        card_type,
        expiration_date,
        {{ hash_diff(['card_type', 'expiration_date']) }} as hash_diff,
        (
            card_type is null or card_type in ('Credit', 'Debit')
        ) as _is_valid,
        current_timestamp as load_dts,
        _source as rec_src
    from cleaned

),

deduped as (

    select
        *,
        row_number() over (partition by hk_card, hash_diff order by load_dts) as rn
    from hashed

),

latest_existing as (

    {% if is_incremental() %}
    select distinct on (hk_card)
        hk_card,
        hash_diff as existing_hash_diff
    from {{ this }}
    order by hk_card, load_dts desc
    {% else %}
    select
        cast(null as varchar) as hk_card,
        cast(null as varchar) as existing_hash_diff
    where false
    {% endif %}

)

select
    d.hk_card,
    d.card_type,
    d.expiration_date,
    d.hash_diff,
    d._is_valid,
    d.load_dts,
    d.rec_src
from deduped d
left join latest_existing le on d.hk_card = le.hk_card
where d.rn = 1
  and (le.existing_hash_diff is null or le.existing_hash_diff <> d.hash_diff)
