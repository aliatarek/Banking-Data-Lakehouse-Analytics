{{ config(materialized='table') }}

select
    customer_id,
    first_name,
    last_name,
    email,
    city,
    credit_score,
    created_at,
    current_timestamp as _loaded_at,
    'kaggle_csv' as _source
from {{ source('bank_raw', 'customers') }}
