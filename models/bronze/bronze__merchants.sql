{{ config(materialized='table') }}

select
    merchant_id,
    merchant_name,
    city,
    current_timestamp as _loaded_at,
    'kaggle_csv' as _source
from {{ source('bank_raw', 'merchants') }}
