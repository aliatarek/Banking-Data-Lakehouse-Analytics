{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        account_id,
        card_id,
        _source
    from {{ ref('bronze__cards') }}

),

hashed as (

    select
        {{ hash_key('account_id') }} as hk_account,
        {{ hash_key('card_id') }} as hk_card,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

hashed_link as (

    select
        {{ link_hash_key(['hk_account', 'hk_card']) }} as hk_link_account_card,
        hk_account,
        hk_card,
        load_dts,
        rec_src
    from hashed

),

deduped as (

    select
        hk_link_account_card,
        hk_account,
        hk_card,
        load_dts,
        rec_src,
        row_number() over (partition by hk_link_account_card order by load_dts) as rn
    from hashed_link

)

select
    hk_link_account_card,
    hk_account,
    hk_card,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and not exists (
    select 1 from {{ this }} existing
    where existing.hk_link_account_card = deduped.hk_link_account_card
  )
{% endif %}
