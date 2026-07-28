{{ config(severity='warn') }}

with latest_loan as (

    select *
    from (
        select
            *,
            row_number() over (partition by hk_loan order by load_dts desc) as rn
        from {{ ref('silver__sat_loan') }}
    ) ranked
    where rn = 1

),

latest_customer as (

    select *
    from (
        select
            *,
            row_number() over (partition by hk_customer order by load_dts desc) as rn
        from {{ ref('silver__sat_customer') }}
    ) ranked
    where rn = 1

)

select
    lo.hk_loan,
    lo.start_date,
    c.hk_customer,
    c.created_at as customer_created_at
from latest_loan lo
inner join {{ ref('silver__link_customer_loan') }} l on l.hk_loan = lo.hk_loan
inner join latest_customer c on c.hk_customer = l.hk_customer
where lo.start_date < c.created_at
