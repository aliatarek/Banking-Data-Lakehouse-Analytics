{{ config(materialized='table') }}

select
    branch_id,
    branch_name,
    manager_name,
    city,
    country,
    current_timestamp as _loaded_at,
    'kaggle_csv' as _source
from {{ source('bank_raw', 'branches') }}
