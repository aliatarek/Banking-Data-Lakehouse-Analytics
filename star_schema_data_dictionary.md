# Gold Star Schema — Data Dictionary

Banking data pipeline (dbt + PostgreSQL). All gold tables live in the **`gold`** schema.

## Overview

- **Architecture:** Kimball star schema built on top of a Data Vault silver layer
- **Dimensions:** SCD Type 2 (multiple rows per entity over time), except `dim_date`
- **Facts:** One row per business event or snapshot; carry **durable hub keys** for joining to dimensions

## How to join (important)

Facts use `*_hub_key` columns. Dimensions can have **multiple rows per hub key** (history).

**Current-state reporting (most common):**

```sql
join gold.dim_customer c
  on c.customer_hub_key = f.customer_hub_key
 and c.is_current
```

**Point-in-time (historical):**

```sql
join gold.dim_customer c
  on c.customer_hub_key = f.customer_hub_key
 and f.transaction_date >= c.effective_start_date
 and f.transaction_date <  c.effective_end_date
```

Join facts to `dim_date` on `date_key` (integer, `yyyymmdd` format).

---

## Dimensions

### `gold.dim_customer` — SCD Type 2

**Grain:** one row per customer **version** (attribute change over time)

| Column | Description |
|---|---|
| `customer_key` | PK — version surrogate (unique per version) |
| `customer_hub_key` | Durable customer key (use to join from facts) |
| `customer_id` | Business key |
| `first_name` | Customer first name |
| `last_name` | Customer last name |
| `email` | Email |
| `city` | City |
| `credit_score` | Credit score (integer) |
| `credit_tier` | Derived bucket: excellent / good / fair / poor / very_poor |
| `created_date` | Customer creation date |
| `acquisition_month` | First day of month from `created_date` |
| `effective_start_date` | Version valid from (timestamp) |
| `effective_end_date` | Version valid until (timestamp); `9999-12-31` if current |
| `is_current` | `true` for the latest version only |
| `record_source` | Data lineage (`kaggle_csv`) |

---

### `gold.dim_account` — SCD Type 2

**Grain:** one row per account **version**

| Column | Description |
|---|---|
| `account_key` | PK — version surrogate |
| `account_hub_key` | Durable account key (join from facts) |
| `account_id` | Business key |
| `customer_hub_key` | Parent customer (from customer–account link) |
| `account_type` | Account type |
| `open_date` | Account open date |
| `effective_start_date` | Version valid from |
| `effective_end_date` | Version valid until |
| `is_current` | Latest version flag |
| `record_source` | Data lineage |

---

### `gold.dim_card` — SCD Type 2

**Grain:** one row per card **version**

**Note:** Not linked directly to any fact. Reach cards via `account_hub_key` → `dim_account`.

| Column | Description |
|---|---|
| `card_key` | PK — version surrogate |
| `card_hub_key` | Durable card key |
| `card_id` | Business key |
| `account_hub_key` | Parent account |
| `card_type` | Card type |
| `expiration_date` | Card expiration date |
| `effective_start_date` | Version valid from |
| `effective_end_date` | Version valid until |
| `is_current` | Latest version flag |
| `record_source` | Data lineage |

---

### `gold.dim_merchant` — SCD Type 2

**Grain:** one row per merchant **version**

| Column | Description |
|---|---|
| `merchant_key` | PK — version surrogate |
| `merchant_hub_key` | Durable merchant key (join from `fact_transactions`) |
| `merchant_id` | Business key |
| `merchant_name` | Merchant name |
| `city` | City |
| `effective_start_date` | Version valid from |
| `effective_end_date` | Version valid until |
| `is_current` | Latest version flag |
| `record_source` | Data lineage |

---

### `gold.dim_branch` — SCD Type 2 (orphan)

**Grain:** one row per branch **version**

**Note:** No fact table references branches today.

| Column | Description |
|---|---|
| `branch_key` | PK — version surrogate |
| `branch_hub_key` | Durable branch key |
| `branch_id` | Business key |
| `branch_name` | Branch name |
| `city` | City |
| `country` | Country |
| `manager_name` | Branch manager |
| `effective_start_date` | Version valid from |
| `effective_end_date` | Version valid until |
| `is_current` | Latest version flag |
| `record_source` | Data lineage |

---

### `gold.dim_date` — static calendar (not SCD2)

**Grain:** one row per calendar day (2015-01-01 .. 2030-01-01)

| Column | Description |
|---|---|
| `date_key` | PK — integer `yyyymmdd` |
| `date_day` | Calendar date |
| `year` | Year |
| `quarter` | Quarter (1-4) |
| `month` | Month (1-12) |
| `month_name` | Month name |
| `day_of_month` | Day of month |
| `day_of_week` | ISO day of week (1=Mon … 7=Sun) |
| `day_name` | Day name |
| `is_weekend` | Weekend flag |
| `week_of_year` | Week of year |
| `day_of_year` | Day of year |
| `is_month_end` | Last day of month flag |

---

## Facts

### `gold.fact_transactions`

**Grain:** 1 row per transaction

| Column | Description |
|---|---|
| `transaction_hub_key` | Grain key / transaction identifier |
| `account_hub_key` | FK → `dim_account` (use with `is_current`) |
| `merchant_hub_key` | FK → `dim_merchant` |
| `customer_hub_key` | FK → `dim_customer` (via account) |
| `date_key` | FK → `dim_date` (from `transaction_date`) |
| `transaction_date` | Event timestamp |
| `amount_usd` | **Measure** — transaction amount |
| `record_source` | Data lineage |
| `load_date` | Load timestamp |

---

### `gold.fact_loans`

**Grain:** 1 row per loan

| Column | Description |
|---|---|
| `loan_hub_key` | Grain key |
| `customer_hub_key` | FK → `dim_customer` |
| `date_key` | FK → `dim_date` (from `start_date`) |
| `start_date` | Loan start date |
| `loan_amount` | **Measure** — loan principal |
| `interest_rate` | **Measure** — interest rate |
| `record_source` | Data lineage |
| `load_date` | Load timestamp |

---

### `gold.fact_account_balance`

**Grain:** 1 row per account (current snapshot)

| Column | Description |
|---|---|
| `account_hub_key` | Grain key / FK → `dim_account` |
| `customer_hub_key` | FK → `dim_customer` |
| `date_key` | FK → `dim_date` (from balance **capture** date) |
| `snapshot_date` | When the balance was captured (`load_date` as date) |
| `open_date` | Account open date (descriptive only — not the time axis) |
| `balance_usd` | **Measure** — current balance |
| `record_source` | Data lineage |
| `load_date` | Load timestamp |

---

## Relationship map

| Table | Joins to |
|---|---|
| `fact_transactions` | `dim_customer`, `dim_account`, `dim_merchant`, `dim_date` |
| `fact_loans` | `dim_customer`, `dim_date` |
| `fact_account_balance` | `dim_customer`, `dim_account`, `dim_date` |
| `dim_card` | Attribute-level via `account_hub_key` → `dim_account` (no direct fact FK) |
| `dim_branch` | No fact links |

---

## Example query — transaction spend by customer city

```sql
select
    c.city,
    d.year,
    d.quarter,
    sum(f.amount_usd) as total_spend
from gold.fact_transactions f
join gold.dim_customer c
  on c.customer_hub_key = f.customer_hub_key
 and c.is_current
join gold.dim_date d
  on d.date_key = f.date_key
group by c.city, d.year, d.quarter
order by d.year, d.quarter, c.city;
```
