{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        account_id,
        account_type,
        balance_usd,
        open_date,
        _source
    from {{ ref('bronze__accounts') }}

),

cleaned as (

    select
        account_id,
        trim(account_type) as account_type,
        balance_usd,
        open_date,
        _source
    from source_data

),

hashed as (

    select
        {{ hash_key('account_id') }} as hk_account,
        account_type,
        balance_usd,
        open_date,
        {{ hash_diff(['account_type', 'balance_usd', 'open_date']) }} as hash_diff,
        (
            (balance_usd is null or balance_usd >= 0)
            and (account_type is null or account_type in ('Business', 'Checking', 'Savings'))
        ) as _is_valid,
        current_timestamp as load_dts,
        _source as rec_src
    from cleaned

),

deduped as (

    select
        *,
        row_number() over (partition by hk_account, hash_diff order by load_dts) as rn
    from hashed

),

latest_existing as (

    {% if is_incremental() %}
    select distinct on (hk_account)
        hk_account,
        hash_diff as existing_hash_diff
    from {{ this }}
    order by hk_account, load_dts desc
    {% else %}
    select
        cast(null as varchar) as hk_account,
        cast(null as varchar) as existing_hash_diff
    where false
    {% endif %}

)

select
    d.hk_account,
    d.account_type,
    d.balance_usd,
    d.open_date,
    d.hash_diff,
    d._is_valid,
    d.load_dts,
    d.rec_src
from deduped d
left join latest_existing le on d.hk_account = le.hk_account
where d.rn = 1
  and (le.existing_hash_diff is null or le.existing_hash_diff <> d.hash_diff)
