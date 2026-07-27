{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        loan_id,
        _source
    from {{ ref('bronze__loans') }}

),

hashed as (

    select
        {{ hash_key('loan_id') }} as hk_loan,
        loan_id,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        hk_loan,
        loan_id,
        load_dts,
        rec_src,
        row_number() over (partition by hk_loan order by load_dts) as rn
    from hashed

)

select
    hk_loan,
    loan_id,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and hk_loan not in (select hk_loan from {{ this }})
{% endif %}
