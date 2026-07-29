{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        customer_id,
        loan_id,
        _source
    from {{ ref('bronze__loans') }}

),

hashed as (

    select
        {{ hash_key('customer_id') }} as hk_customer,
        {{ hash_key('loan_id') }} as hk_loan,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

hashed_link as (

    select
        {{ link_hash_key(['hk_customer', 'hk_loan']) }} as hk_link_customer_loan,
        hk_customer,
        hk_loan,
        load_dts,
        rec_src
    from hashed

),

deduped as (

    select
        hk_link_customer_loan,
        hk_customer,
        hk_loan,
        load_dts,
        rec_src,
        row_number() over (partition by hk_link_customer_loan order by load_dts) as rn
    from hashed_link

)

select
    hk_link_customer_loan,
    hk_customer,
    hk_loan,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and not exists (
    select 1 from {{ this }} existing
    where existing.hk_link_customer_loan = deduped.hk_link_customer_loan
  )
{% endif %}
