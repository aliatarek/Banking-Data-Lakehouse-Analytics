{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        account_id,
        _source
    from {{ ref('bronze__accounts') }}

),

hashed as (

    select
        {{ hash_key('account_id') }} as hk_account,
        account_id,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        hk_account,
        account_id,
        load_dts,
        rec_src,
        row_number() over (partition by hk_account order by load_dts) as rn
    from hashed

)

select
    hk_account,
    account_id,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and not exists (
    select 1 from {{ this }} existing
    where existing.hk_account = deduped.hk_account
  )
{% endif %}
