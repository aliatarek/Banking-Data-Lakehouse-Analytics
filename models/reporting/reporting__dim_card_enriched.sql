with current_cards as (

    select
        card_hub_key,
        card_id,
        account_hub_key,
        card_type,
        expiration_date::date as expiration_date
    from {{ ref('gold__dim_card') }}
    where is_current

),

current_accounts as (

    select
        account_hub_key,
        account_id,
        customer_hub_key,
        account_type
    from {{ ref('gold__dim_account') }}
    where is_current

),

current_customers as (

    select
        customer_hub_key,
        customer_id,
        credit_tier,
        city
    from {{ ref('gold__dim_customer') }}
    where is_current
)

select
    cc.card_hub_key,
    cc.card_id,
    cc.account_hub_key,
    ca.account_id,
    ca.account_type,
    ca.customer_hub_key,
    cu.customer_id,
    cu.credit_tier,
    cu.city as customer_city,
    cc.card_type,
    cc.expiration_date,
    cc.expiration_date - current_date as days_to_expiration,
    case when cc.expiration_date <= current_date + 30 then true else false end as expires_within_30_days,
    case when cc.expiration_date <= current_date + 60 then true else false end as expires_within_60_days,
    case when cc.expiration_date <= current_date + 90 then true else false end as expires_within_90_days,
    current_date as snapshot_date
from current_cards cc
inner join current_accounts ca on ca.account_hub_key = cc.account_hub_key
left join current_customers cu on cu.customer_hub_key = ca.customer_hub_key
