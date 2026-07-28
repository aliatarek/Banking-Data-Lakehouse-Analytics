with current_cards as (

    select
        hk_card as card_hub_key,
        card_id,
        card_type,
        expiration_date::date as expiration_date
    from {{ ref('gold__dim_card') }}

),

current_accounts as (

    select
        hk_account as account_hub_key,
        account_id,
        account_type
    from {{ ref('gold__dim_account') }}

),

current_customers as (

    select
        hk_customer as customer_hub_key,
        customer_id,
        case
            when credit_score is null then null
            when credit_score >= 800 then 'excellent'
            when credit_score >= 740 then 'good'
            when credit_score >= 670 then 'fair'
            when credit_score >= 580 then 'poor'
            else 'very_poor'
        end as credit_tier,
        city
    from {{ ref('gold__dim_customer') }}

),

customer_accounts as (

    select
        hk_account as account_hub_key,
        hk_customer as customer_hub_key
    from {{ ref('silver__link_customer_account') }}

),

account_cards as (

    select
        hk_account as account_hub_key,
        hk_card as card_hub_key
    from {{ ref('silver__link_account_card') }}
)

select
    cc.card_hub_key,
    cc.card_id,
    ac.account_hub_key,
    ca.account_id,
    ca.account_type,
    lca.customer_hub_key,
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
inner join account_cards ac on ac.card_hub_key = cc.card_hub_key
inner join current_accounts ca on ca.account_hub_key = ac.account_hub_key
left join customer_accounts lca on lca.account_hub_key = ac.account_hub_key
left join current_customers cu on cu.customer_hub_key = lca.customer_hub_key
