{{ config(materialized='table') }}

select
    account_id,
    customer_id,
    account_type,
    balance_usd,
    open_date,
    current_timestamp as _loaded_at,
    'kaggle_csv' as _source
from {{ source('bank_raw', 'accounts') }}
