{{ config(materialized='table') }}

select
    transaction_id,
    account_id,
    merchant_id,
    amount_usd,
    transaction_date,
    current_timestamp as _loaded_at,
    'kaggle_csv' as _source
from {{ source('bank_raw', 'transactions') }}
