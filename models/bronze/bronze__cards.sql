{{ config(materialized='table') }}

select
    card_id,
    account_id,
    card_type,
    expiration_date,
    current_timestamp as _loaded_at,
    'kaggle_csv' as _source
from {{ source('bank_raw', 'cards') }}
