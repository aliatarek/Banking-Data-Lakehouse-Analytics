{{ config(severity='warn') }}

with latest_account as (

    select *
    from (
        select
            *,
            row_number() over (partition by hk_account order by load_dts desc) as rn
        from {{ ref('silver__sat_account') }}
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
    a.hk_account,
    a.open_date,
    c.hk_customer,
    c.created_at as customer_created_at
from latest_account a
inner join {{ ref('silver__link_customer_account') }} l on l.hk_account = a.hk_account
inner join latest_customer c on c.hk_customer = l.hk_customer
where a.open_date < c.created_at
