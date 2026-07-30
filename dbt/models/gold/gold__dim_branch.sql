{{ config(materialized='table') }}

with sat as (

    select
        hk_branch,
        branch_name,
        manager_name,
        city,
        country,
        load_dts,
        rec_src
    from {{ ref('silver__sat_branch') }}

),

hub as (

    select
        hk_branch,
        branch_id
    from {{ ref('silver__hub_branch') }}

),

versioned as (

    select
        s.hk_branch,
        h.branch_id,
        s.branch_name,
        s.manager_name,
        s.city,
        s.country,
        s.load_dts,
        s.rec_src,
        lead(s.load_dts) over (partition by s.hk_branch order by s.load_dts) as next_load_dts
    from sat s
    inner join hub h on h.hk_branch = s.hk_branch

)

select
    {{ surrogate_key(['hk_branch', 'load_dts']) }} as branch_key,
    hk_branch as branch_hub_key,
    branch_id,
    branch_name,
    city,
    country,
    manager_name,
    load_dts as effective_start_date,
    coalesce(next_load_dts, '9999-12-31'::timestamp) as effective_end_date,
    (next_load_dts is null) as is_current,
    rec_src as record_source
from versioned
