{{ config(materialized='table') }}

with sat as (

    select
        hk_customer,
        first_name,
        last_name,
        email,
        city,
        credit_score,
        created_at,
        load_dts,
        rec_src
    from {{ ref('silver__sat_customer') }}

),

hub as (

    select
        hk_customer,
        customer_id
    from {{ ref('silver__hub_customer') }}

),

versioned as (

    select
        s.hk_customer,
        h.customer_id,
        s.first_name,
        s.last_name,
        s.email,
        s.city,
        s.credit_score,
        s.created_at,
        s.load_dts,
        s.rec_src,
        lead(s.load_dts) over (partition by s.hk_customer order by s.load_dts) as next_load_dts
    from sat s
    inner join hub h on h.hk_customer = s.hk_customer

)

select
    {{ surrogate_key(['hk_customer', 'load_dts']) }} as customer_key,
    hk_customer as customer_hub_key,
    customer_id,
    first_name,
    last_name,
    email,
    city,
    credit_score,
    case
        when credit_score is null then null
        when credit_score >= 800 then 'excellent'
        when credit_score >= 740 then 'good'
        when credit_score >= 670 then 'fair'
        when credit_score >= 580 then 'poor'
        else 'very_poor'
    end as credit_tier,
    created_at::date as created_date,
    date_trunc('month', created_at)::date as acquisition_month,
    load_dts as effective_start_date,
    coalesce(next_load_dts, '9999-12-31'::timestamp) as effective_end_date,
    (next_load_dts is null) as is_current,
    rec_src as record_source
from versioned
