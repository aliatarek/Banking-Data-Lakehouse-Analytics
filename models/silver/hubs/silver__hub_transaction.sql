{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        transaction_id,
        _source
    from {{ ref('bronze__transactions') }}

),

hashed as (

    select
        {{ hash_key('transaction_id') }} as hk_transaction,
        transaction_id,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        hk_transaction,
        transaction_id,
        load_dts,
        rec_src,
        row_number() over (partition by hk_transaction order by load_dts) as rn
    from hashed

)

select
    hk_transaction,
    transaction_id,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and hk_transaction not in (select hk_transaction from {{ this }})
{% endif %}
