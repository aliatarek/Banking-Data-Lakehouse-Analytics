with current_cards as (

    select
        account_hub_key,
        card_type
    from {{ ref('gold__dim_card') }}
    where is_current

),

current_accounts as (

    select
        account_hub_key,
        account_type
    from {{ ref('gold__dim_account') }}
    where is_current

)

select
    ca.account_type,
    cc.card_type,
    count(*) as card_count
from current_cards cc
inner join current_accounts ca on ca.account_hub_key = cc.account_hub_key
group by 1, 2
