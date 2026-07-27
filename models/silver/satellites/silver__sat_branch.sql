{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        branch_id,
        branch_name,
        manager_name,
        city,
        country,
        _source
    from {{ ref('bronze__branches') }}

),

cleaned as (

    select
        branch_id,
        initcap(trim(branch_name)) as branch_name,
        initcap(trim(manager_name)) as manager_name,
        initcap(trim(city)) as city,
        trim(country) as country,
        _source
    from source_data

),

hashed as (

    select
        {{ hash_key('branch_id') }} as hk_branch,
        branch_name,
        manager_name,
        city,
        country,
        {{ hash_diff(['branch_name', 'manager_name', 'city', 'country']) }} as hash_diff,
        (
            branch_name is not null and branch_name <> ''
        ) as _is_valid,
        current_timestamp as load_dts,
        _source as rec_src
    from cleaned

),

deduped as (

    select
        *,
        row_number() over (partition by hk_branch, hash_diff order by load_dts) as rn
    from hashed

),

latest_existing as (

    {% if is_incremental() %}
    select distinct on (hk_branch)
        hk_branch,
        hash_diff as existing_hash_diff
    from {{ this }}
    order by hk_branch, load_dts desc
    {% else %}
    select
        cast(null as varchar) as hk_branch,
        cast(null as varchar) as existing_hash_diff
    where false
    {% endif %}

)

select
    d.hk_branch,
    d.branch_name,
    d.manager_name,
    d.city,
    d.country,
    d.hash_diff,
    d._is_valid,
    d.load_dts,
    d.rec_src
from deduped d
left join latest_existing le on d.hk_branch = le.hk_branch
where d.rn = 1
  and (le.existing_hash_diff is null or le.existing_hash_diff <> d.hash_diff)
