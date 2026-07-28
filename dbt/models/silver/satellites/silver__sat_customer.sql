{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        customer_id,
        first_name,
        last_name,
        email,
        city,
        credit_score,
        created_at,
        _source
    from {{ ref('bronze__customers') }}

),

cleaned as (

    select
        customer_id,
        initcap(trim(first_name)) as first_name,
        initcap(trim(last_name)) as last_name,
        lower(trim(email)) as email,
        initcap(trim(city)) as city,
        credit_score,
        created_at,
        _source
    from source_data

),

hashed as (

    select
        {{ hash_key('customer_id') }} as hk_customer,
        first_name,
        last_name,
        email,
        city,
        credit_score,
        created_at,
        {{ hash_diff(['first_name', 'last_name', 'email', 'city', 'credit_score', 'created_at']) }} as hash_diff,
        (
            (email is null or email ~ '^[^@]+@[^@]+\.[^@]+$')
            and (credit_score is null or credit_score between 300 and 850)
            and (created_at is null or created_at <= current_timestamp)
        ) as _is_valid,
        current_timestamp as load_dts,
        _source as rec_src
    from cleaned

),

deduped as (

    select
        *,
        row_number() over (partition by hk_customer, hash_diff order by load_dts) as rn
    from hashed

),

latest_existing as (

    {% if is_incremental() %}
    select distinct on (hk_customer)
        hk_customer,
        hash_diff as existing_hash_diff
    from {{ this }}
    order by hk_customer, load_dts desc
    {% else %}
    select
        cast(null as varchar) as hk_customer,
        cast(null as varchar) as existing_hash_diff
    where false
    {% endif %}

)

select
    d.hk_customer,
    d.first_name,
    d.last_name,
    d.email,
    d.city,
    d.credit_score,
    d.created_at,
    d.hash_diff,
    d._is_valid,
    d.load_dts,
    d.rec_src
from deduped d
left join latest_existing le on d.hk_customer = le.hk_customer
where d.rn = 1
  and (le.existing_hash_diff is null or le.existing_hash_diff <> d.hash_diff)
