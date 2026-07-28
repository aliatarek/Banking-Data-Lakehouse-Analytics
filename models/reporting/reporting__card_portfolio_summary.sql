with current_cards as (

    select
        lac.hk_account as account_hub_key,
        card_type
    from {{ ref('gold__dim_card') }} dc
    inner join {{ ref('silver__link_account_card') }} lac on lac.hk_card = dc.hk_card

),

current_accounts as (

    select
        hk_account as account_hub_key,
        account_type
    from {{ ref('gold__dim_account') }}

)

select
    ca.account_type,
    cc.card_type,
    count(*) as card_count
from current_cards cc
inner join current_accounts ca on ca.account_hub_key = cc.account_hub_key
group by 1, 2
