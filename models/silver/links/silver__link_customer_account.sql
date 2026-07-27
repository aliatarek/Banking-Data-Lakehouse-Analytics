{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        customer_id,
        account_id,
        _source
    from {{ ref('bronze__accounts') }}

),

hashed as (

    select
        {{ hash_key('customer_id') }} as hk_customer,
        {{ hash_key('account_id') }} as hk_account,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

hashed_link as (

    select
        {{ link_hash_key(['hk_customer', 'hk_account']) }} as hk_link_customer_account,
        hk_customer,
        hk_account,
        load_dts,
        rec_src
    from hashed

),

deduped as (

    select
        hk_link_customer_account,
        hk_customer,
        hk_account,
        load_dts,
        rec_src,
        row_number() over (partition by hk_link_customer_account order by load_dts) as rn
    from hashed_link

)

select
    hk_link_customer_account,
    hk_customer,
    hk_account,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and hk_link_customer_account not in (select hk_link_customer_account from {{ this }})
{% endif %}
