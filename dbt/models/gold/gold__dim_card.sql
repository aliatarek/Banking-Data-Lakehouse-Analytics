{{ config(materialized='table') }}

with sat as (

    select
        hk_card,
        card_type,
        expiration_date,
        load_dts,
        rec_src
    from {{ ref('silver__sat_card') }}

),

hub as (

    select
        hk_card,
        card_id
    from {{ ref('silver__hub_card') }}

),

link as (

    select
        hk_card,
        hk_account
    from {{ ref('silver__link_account_card') }}

),

versioned as (

    select
        s.hk_card,
        h.card_id,
        l.hk_account,
        s.card_type,
        s.expiration_date,
        s.load_dts,
        s.rec_src,
        lead(s.load_dts) over (partition by s.hk_card order by s.load_dts) as next_load_dts
    from sat s
    inner join hub h on h.hk_card = s.hk_card
    inner join link l on l.hk_card = s.hk_card

)

select
    {{ surrogate_key(['hk_card', 'load_dts']) }} as card_key,
    hk_card as card_hub_key,
    card_id,
    hk_account as account_hub_key,
    card_type,
    expiration_date,
    load_dts as effective_start_date,
    coalesce(next_load_dts, '9999-12-31'::timestamp) as effective_end_date,
    (next_load_dts is null) as is_current,
    rec_src as record_source
from versioned
