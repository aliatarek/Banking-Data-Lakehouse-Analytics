{{ config(materialized='table') }}

with sat as (

    select
        hk_loan,
        loan_amount,
        interest_rate,
        start_date,
        load_dts,
        rec_src
    from {{ ref('silver__sat_loan') }}

),

link as (

    select
        hk_loan,
        hk_customer
    from {{ ref('silver__link_customer_loan') }}

)

select
    s.hk_loan as loan_hub_key,
    l.hk_customer as customer_hub_key,
    to_char(s.start_date, 'YYYYMMDD')::int as date_key,
    s.start_date,
    s.loan_amount,
    s.interest_rate,
    s.rec_src as record_source,
    s.load_dts as load_date
from sat s
inner join link l on l.hk_loan = s.hk_loan
