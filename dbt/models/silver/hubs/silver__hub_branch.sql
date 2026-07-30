{{ config(
    materialized='incremental',
    incremental_strategy='append'
) }}

with source_data as (

    select
        branch_id,
        _source
    from {{ ref('bronze__branches') }}

),

hashed as (

    select
        {{ hash_key('branch_id') }} as hk_branch,
        branch_id,
        current_timestamp as load_dts,
        _source as rec_src
    from source_data

),

deduped as (

    select
        hk_branch,
        branch_id,
        load_dts,
        rec_src,
        row_number() over (partition by hk_branch order by load_dts) as rn
    from hashed

)

select
    hk_branch,
    branch_id,
    load_dts,
    rec_src
from deduped
where rn = 1

{% if is_incremental() %}
  and not exists (
    select 1 from {{ this }} existing
    where existing.hk_branch = deduped.hk_branch
  )
{% endif %}
