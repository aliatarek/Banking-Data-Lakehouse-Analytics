{{ config(materialized='table') }}

select
    loan_id,
    customer_id,
    loan_amount,
    interest_rate,
    start_date,
    current_timestamp as _loaded_at,
    'kaggle_csv' as _source
from {{ source('bank_raw', 'loans') }}
