{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        loan_id,
        loan_amount,
        interest_rate,
        start_date,
        _source
    from {{ ref('bronze__loans') }}

),

hashed as (

    select
        {{ hash_key('loan_id') }} as hk_loan,
        loan_amount,
        interest_rate,
        start_date,
        {{ hash_diff(['loan_amount', 'interest_rate', 'start_date']) }} as hash_diff,
        (
            (loan_amount is null or loan_amount > 0)
            and (interest_rate is null or interest_rate between 0 and 100)
        ) as _is_valid,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        *,
        row_number() over (partition by hk_loan, hash_diff order by load_dts) as rn
    from hashed

),

latest_existing as (

    {% if is_incremental() %}
    select distinct on (hk_loan)
        hk_loan,
        hash_diff as existing_hash_diff
    from {{ this }}
    order by hk_loan, load_dts desc
    {% else %}
    select
        cast(null as varchar) as hk_loan,
        cast(null as varchar) as existing_hash_diff
    where false
    {% endif %}

)

select
    d.hk_loan,
    d.loan_amount,
    d.interest_rate,
    d.start_date,
    d.hash_diff,
    d._is_valid,
    d.load_dts,
    d.rec_src
from deduped d
left join latest_existing le on d.hk_loan = le.hk_loan
where d.rn = 1
  and (le.existing_hash_diff is null or le.existing_hash_diff <> d.hash_diff)
