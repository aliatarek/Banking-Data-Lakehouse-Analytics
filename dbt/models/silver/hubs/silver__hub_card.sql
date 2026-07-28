{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        card_id,
        _source
    from {{ ref('bronze__cards') }}

),

hashed as (

    select
        {{ hash_key('card_id') }} as hk_card,
        card_id,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        hk_card,
        card_id,
        load_dts,
        rec_src,
        row_number() over (partition by hk_card order by load_dts) as rn
    from hashed

)

select
    hk_card,
    card_id,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and hk_card not in (select hk_card from {{ this }})
{% endif %}
