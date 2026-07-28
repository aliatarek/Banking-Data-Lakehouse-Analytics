select
    date_trunc('month', start_date)::date as origination_month,
    count(*) as loan_count,
    coalesce(sum(loan_amount), 0) as total_loan_amount_usd,
    coalesce(avg(interest_rate), 0) as avg_interest_rate
from {{ ref('gold__fact_loans') }}
group by 1
