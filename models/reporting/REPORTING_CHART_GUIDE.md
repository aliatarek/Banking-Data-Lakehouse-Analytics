# Reporting chart guide

Use the `reporting` schema for dashboard datasets. Each table below is already shaped for one business use case, so teammates should not need to join against `gold`.

## KPI charts

1. `K1 Total Customers`
   - Dataset: `reporting__customer_kpis`
   - Metric: `total_customers`

2. `K2 Total Deposits`
   - Dataset: `reporting__customer_kpis`
   - Metric: `total_deposits_usd`

3. `K3 Total Loan Book`
   - Dataset: `reporting__customer_kpis`
   - Metric: `total_loan_book_usd`

4. `K4 Total Transaction Volume`
   - Dataset: `reporting__customer_kpis`
   - Metric: `total_transaction_volume_usd`

## Customer growth and acquisition

5. `New Customers per Month`
   - Dataset: `reporting__monthly_customer_growth`
   - Time column: `acquisition_month`
   - Metric: `new_customers`

6. `New Accounts per year by Type`
   - Dataset: `reporting__yearly_account_openings_by_type`
   - Time column: `open_year`
   - Group by: `account_type`
   - Metric: `new_accounts`

7. `% Customers with Multiple Accounts`
   - Dataset: `reporting__customer_kpis`
   - Metric: `pct_customers_with_multiple_accounts`

## Deposits and balances

8. `Total Deposits by Account Type`
   - Dataset: `reporting__account_type_deposits`
   - Group by: `account_type`
   - Metric: `total_balance_usd`

9. `Account Opening Trend by Cohort`
   - Dataset: `reporting__account_opening_cohort_trend`
   - Time column: `open_month`
   - Group by: `account_type`
   - Metric: `total_balance_usd`
   - Note: this is an open-date proxy using current balances

10. `Average Balance per Customer`
    - Dataset: `reporting__customer_balance_kpis`
    - Metric: `avg_balance_usd`

11. `Median Balance per Customer`
    - Dataset: `reporting__customer_balance_kpis`
    - Metric: `median_balance_usd`

average helps with business size
median helps with customer reality

12. `Deposit Concentration`
    - Dataset: `reporting__customer_balance_summary`
    - Sort by: `balance_rank` or `total_balance_usd desc`
    - Metric: `total_balance_usd`
    - Group by / label: `customer_id`

## Lending and credit risk

13. `Loan Originations Trend`
    - Dataset: `reporting__loan_monthly_trend`
    - Time column: `origination_month`
    - Metric: `total_loan_amount_usd`

14. `Interest Rate vs Credit Tier`
    - Dataset: `reporting__interest_rate_by_credit_tier`
    - Group by: `credit_tier`
    - Sort by: `credit_tier_sort_order`
    - Metric: `avg_interest_rate`

15. `Loan Penetration by Credit Tier`
    - Dataset: `reporting__loan_penetration_by_credit_tier`
    - Group by: `credit_tier`
    - Sort by: `credit_tier_sort_order`
    - Metric: `loan_penetration_pct`

16. `Credit Tier Mix Over Time`
    - Dataset: `reporting__customer_credit_mix_monthly`
    - Time column: `acquisition_month`
    - Group by: `credit_tier`
    - Sort by: `credit_tier_sort_order`
    - Metric: `pct_of_month_total`

## Card portfolio

17. `Debit vs Credit Mix by Account Type`
    - Dataset: `reporting__dim_card_enriched`
    - Group by: `account_type`
    - Series / group: `card_type`
    - Metric: `count(card_id)`

18. `Cards Expiring Soon`
    - Preferred dataset: `reporting__card_expiry_buckets`
    - Filter each tile by `bucket_days` = `30`, `60`, or `90`
    - Metric: `cards_expiring_count`
    - Alternate dataset if the BI tool needs row-level filtering: `reporting__dim_card_enriched` using `expires_within_30_days`, `expires_within_60_days`, or `expires_within_90_days`

## Transaction activity and spend

19. `Transaction Volume and Count by Month`
    - Dataset: `reporting__transaction_monthly_summary`
    - Time column: `transaction_month`
    - Metrics: `total_transaction_volume_usd` and `transaction_count`

20. `Top Merchants by Volume`
    - Dataset: `reporting__top_merchants`
    - Group by / label: `merchant_name`
    - Metric: `total_transaction_volume_usd`
    - Sort by: `volume_rank` or `total_transaction_volume_usd desc`

21. `Average Transaction Size by Account Type`
    - Dataset: `reporting__avg_transaction_by_account_type`
    - Group by: `account_type`
    - Metric: `avg_transaction_amount_usd`
