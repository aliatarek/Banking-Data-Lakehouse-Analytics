{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        account_id,
        transaction_id,
        _source
    from {{ ref('bronze__transactions') }}

),

hashed as (

    select
        {{ hash_key('account_id') }} as hk_account,
        {{ hash_key('transaction_id') }} as hk_transaction,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

hashed_link as (

    select
        {{ link_hash_key(['hk_account', 'hk_transaction']) }} as hk_link_account_transaction,
        hk_account,
        hk_transaction,
        load_dts,
        rec_src
    from hashed

),

deduped as (

    select
        hk_link_account_transaction,
        hk_account,
        hk_transaction,
        load_dts,
        rec_src,
        row_number() over (partition by hk_link_account_transaction order by load_dts) as rn
    from hashed_link

)

select
    hk_link_account_transaction,
    hk_account,
    hk_transaction,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and hk_link_account_transaction not in (select hk_link_account_transaction from {{ this }})
{% endif %}
