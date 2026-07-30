{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        transaction_id,
        amount_usd,
        transaction_date,
        _source
    from {{ ref('bronze__transactions') }}

),

hashed as (

    select
        {{ hash_key('transaction_id') }} as hk_transaction,
        amount_usd,
        transaction_date,
        {{ hash_diff(['amount_usd', 'transaction_date']) }} as hash_diff,
        (
            (amount_usd is null or amount_usd > 0)
            and (transaction_date is null or transaction_date <= current_timestamp)
        ) as _is_valid,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        *,
        row_number() over (partition by hk_transaction, hash_diff order by load_dts) as rn
    from hashed

),

latest_existing as (

    {% if is_incremental() %}
    select distinct on (hk_transaction)
        hk_transaction,
        hash_diff as existing_hash_diff
    from {{ this }}
    order by hk_transaction, load_dts desc
    {% else %}
    select
        cast(null as varchar) as hk_transaction,
        cast(null as varchar) as existing_hash_diff
    where false
    {% endif %}

)

select
    d.hk_transaction,
    d.amount_usd,
    d.transaction_date,
    d.hash_diff,
    d._is_valid,
    d.load_dts,
    d.rec_src
from deduped d
left join latest_existing le on d.hk_transaction = le.hk_transaction
where d.rn = 1
  and (le.existing_hash_diff is null or le.existing_hash_diff <> d.hash_diff)
