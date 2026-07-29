# Reporting metric cheat sheet

This guide tells dashboard builders which aggregation to choose in Superset for each reporting dataset.

## Core rule

- Use `MAX(...)` for one-row KPI tables where the value is already fully computed.
- Use `SUM(...)` for pre-aggregated tables with one row per month, type, tier, or merchant where you want totals across visible rows.
- Use `COUNT(...)` for row-level tables where each row is one entity, such as one card.
- Avoid `SUM(...)` on precomputed percentages or averages unless you intentionally want to add them across rows.

## KPI charts

1. `K1 Total Customers`
   - Dataset: `reporting__customer_kpis`
   - Metric: `MAX(total_customers)`

2. `K2 Total Deposits`
   - Dataset: `reporting__customer_kpis`
   - Metric: `MAX(total_deposits_usd)`

3. `K3 Total Loan Book`
   - Dataset: `reporting__customer_kpis`
   - Metric: `MAX(total_loan_book_usd)`

4. `K4 Total Transaction Volume`
   - Dataset: `reporting__customer_kpis`
   - Metric: `MAX(total_transaction_volume_usd)`

## The 14 non-KPI charts

1. `New Customers per Month`
   - Dataset: `reporting__monthly_customer_growth`
   - Metric: `SUM(new_customers)`

2. `New Accounts per Month by Type`
   - Dataset: `reporting__monthly_account_openings_by_type`
   - Metric: `SUM(new_accounts)`

3. `% Customers with Multiple Accounts`
   - Dataset: `reporting__customer_kpis`
   - Metric: `MAX(pct_customers_with_multiple_accounts)`

4. `Total Deposits by Account Type`
   - Dataset: `reporting__account_type_deposits`
   - Metric: `SUM(total_balance_usd)`

4b. `Account Opening Trend by Cohort`
   - Dataset: `reporting__account_opening_cohort_trend`
   - Metric: `SUM(total_balance_usd)`
   - Note: This is an open-date proxy using current balances.

5. `Average Balance per Customer`
   - Dataset: `reporting__customer_balance_kpis`
   - Metric: `MAX(avg_balance_usd)`

5. `Median Balance per Customer`
   - Dataset: `reporting__customer_balance_kpis`
   - Metric: `MAX(median_balance_usd)`

5b. `Deposit Concentration`
   - Dataset: `reporting__customer_balance_summary`
   - Metric: `SUM(total_balance_usd)`
   - Group by: `customer_id`

6. `Loan Originations Trend`
   - Dataset: `reporting__loan_monthly_trend`
   - Metric: `SUM(total_loan_amount_usd)`

7. `Interest Rate vs Credit Tier`
   - Dataset: `reporting__interest_rate_by_credit_tier`
   - Metric: `MAX(avg_interest_rate)`
   - Sort by: `credit_tier_sort_order`

8. `Loan Penetration by Credit Tier`
   - Dataset: `reporting__loan_penetration_by_credit_tier`
   - Metric: `MAX(loan_penetration_pct)`
   - Sort by: `credit_tier_sort_order`

9. `Credit Tier Mix Over Time`
   - Dataset: `reporting__customer_credit_mix_monthly`
   - Metric: `SUM(pct_of_month_total)`
   - Group by: `credit_tier`
   - Note: This is intended for 100% stacked charts.

10. `Debit vs Credit Mix by Account Type`
    - Dataset: `reporting__dim_card_enriched`
    - Metric: `COUNT(card_id)`
    - Group by: `account_type`
    - Series: `card_type`

11. `Cards Expiring Soon`
    - Dataset: `reporting__card_expiry_buckets`
    - Metric: `MAX(cards_expiring_count)`
    - Filter: `bucket_days = 30`, `60`, or `90`

12. `Transaction Volume and Count by Month`
    - Dataset: `reporting__transaction_monthly_summary`
    - Metrics:
      - `SUM(total_transaction_volume_usd)`
      - `SUM(transaction_count)`

13. `Top Merchants by Volume`
    - Dataset: `reporting__top_merchants`
    - Metric: `SUM(total_transaction_volume_usd)`
    - Group by: `merchant_name`

14. `Average Transaction Size by Account Type`
    - Dataset: `reporting__avg_transaction_by_account_type`
    - Metric: `MAX(avg_transaction_amount_usd)`

## Quick sanity check

- If the table has exactly one row, prefer `MAX`.
- If the table has one row per category or month and stores totals, use `SUM`.
- If the table has one row per entity and you want to count entities, use `COUNT`.
