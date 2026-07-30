select
    date_trunc('month', transaction_date)::date as transaction_month,
    count(*) as transaction_count,
    coalesce(sum(amount_usd), 0) as total_transaction_volume_usd,
    coalesce(avg(amount_usd), 0) as avg_transaction_amount_usd
from {{ ref('gold__fact_transactions') }}
group by 1
