# Banking Data Lakehouse Analytics

A medallion-architecture data pipeline that transforms a synthetic retail banking dataset (1.26M+ records across 7 source tables) into an analytics-ready star schema, built with **dbt + PostgreSQL**.

```
Raw OLTP tables (public schema)
        │
        ▼
   BRONZE  — 1:1 raw copy, no transformation
        │
        ▼
   SILVER  — Data Vault 2.0 (hubs, links, satellites, quarantine)
        │
        ▼
    GOLD   — Kimball star schema (SCD Type 2 dimensions + facts)
        │
        ▼
 REPORTING — one flat, pre-aggregated table per BI chart
```

---

## Data source

Synthetic retail banking dataset: `customers`, `accounts`, `cards`, `merchants`, `branches`, `loans`, `transactions` (Kaggle: `akrambelha/synthetic-banking-dataset-csv-sql-sqlite`). Raw DDL and seed data live in [`../sql`](../sql) (`schema.sql` + `*_inserts.sql`), loaded into a `public` schema before dbt touches anything.

Known gaps in the source data (not fabricated anywhere downstream — see [Known limitations](#known-limitations)):
- No FK linking `branches` to accounts/transactions — orphan dimension
- No `transaction_type` (can't distinguish debit/credit)
- No `loan_status`/repayment tracking
- No customer demographics beyond city/credit_score
- No `account_status`
- `open_date`, `start_date`, and `transaction_date` were generated independently of `created_at` per entity, so a meaningful fraction of rows have a "child" date earlier than its "parent" date (see the warn-severity tests)

---

## Architecture

### Bronze (`bronze` schema)

Straight passthrough of the raw tables via `source()`, no cleaning or filtering. Adds `_loaded_at` / `_source` metadata columns. Materialized as `table` (full refresh each run).

Models: `bronze__customers`, `bronze__accounts`, `bronze__cards`, `bronze__merchants`, `bronze__branches`, `bronze__loans`, `bronze__transactions`.

### Silver (`silver` schema) — Data Vault 2.0

Historized, audit-ready integration layer separating structure from context:

- **Hubs** (7) — one per business entity, hash key `hk_<entity> = MD5(UPPER(TRIM(business_key)))`, insert-only.
- **Links** (5) — one per FK relationship, hash key `MD5(CONCAT(hub1_key, hub2_key))`, insert-only. No link for `branches` (orphan).
- **Satellites** (7) — descriptive attributes with `hash_diff`-based change detection (new row only when data actually changes), basic cleaning (`TRIM`, `LOWER` on email, `INITCAP` on names/cities), and an inline `_is_valid` flag computed from the single-table data-quality rules (email format, numeric ranges, not-in-future dates).
- **Quarantine** — unions every satellite's `_is_valid = false` rows into one table with the rejection reason and the natural business key (recovered via the parent hub). Rebuilt in full each run; a soft-fail mechanism, doesn't block Gold.

All hubs/links/satellites are `incremental` + `append` — idempotent by construction (hashing + hash-diff comparison means re-running against unchanged source data produces zero new rows).

### Gold (`gold` schema) — Kimball star schema

6 SCD Type 2 dimensions (`dim_customer`, `dim_account`, `dim_card`, `dim_merchant`, `dim_branch`, plus static `dim_date`) and 3 facts (`fact_transactions`, `fact_loans`, `fact_account_balance`).

- Dimensions carry a version-level surrogate key (`*_key`) and a durable key (`*_hub_key`) that facts join on — never join on `*_key` directly, since a dimension can have multiple rows per entity over time.
- `effective_start_date`/`effective_end_date` are precomputed at build time via `LEAD(load_dts)` over each hub key (open-ended rows get `9999-12-31`), plus an `is_current` flag — see the full column reference in [`star_schema_data_dictionary.md`](./star_schema_data_dictionary.md).
- `dim_customer.credit_tier`: excellent (800-850), good (740-799), fair (670-739), poor (580-669), very_poor (300-579).
- `fact_account_balance` is a **current snapshot** (one row per account, latest satellite version only) — the source system only ever exposes a current balance, so this cannot be a true balance-over-time fact.
- `dim_date` spans 2015-01-01 to 2030-01-01 inclusive (5,480 days), generated with an explicit upper-bound filter rather than relying on `generate_series`'s implicit endpoint inclusion, which differs between Postgres patch versions.

### Reporting (`reporting` schema)

One pre-shaped, pre-aggregated table per BI chart/question, sitting on top of Gold so dashboard tools don't need to join or compute KPIs themselves. See [`models/reporting/REPORTING_CHART_GUIDE.md`](models/reporting/REPORTING_CHART_GUIDE.md) for the full chart-to-dataset mapping (customer growth, deposits, lending, credit risk, card portfolio, transaction activity).

---

## Testing

166 dbt tests across all four layers:

- Structural: `unique`/`not_null` on every hash key and business key, `relationships` on every FK, `accepted_values` on categoricals (`account_type`, `card_type`, `credit_tier`).
- Custom generic tests (`tests/generic/`): `valid_email`, `not_in_future`, `positive_value`, `in_range` (optional upper bound), `not_empty_string`, `single_current_version` (SCD2 invariant: exactly one `is_current` row per hub key).
- Singular cross-entity tests (`tests/`): account/loan open dates vs. customer creation date, transaction date vs. account open date — configured `severity: warn` since these fail against a real, unfixable characteristic of the synthetic data (see [Known limitations](#known-limitations)), not a modeling bug.

Run everything with `dbt test` (or `dbt build` to run models + tests together).

---

## Prerequisites

- PostgreSQL (tested against 18.x)
- Python 3.10+ and `dbt-postgres` (`pip install dbt-postgres`)
- The raw dataset loaded into a Postgres database (see below)

## Setup

**1. Create the database, then load the schema and raw data:**

```bash
createdb scb_proj
```

> **Note:** `../sql/schema.sql` opens with `CREATE DATABASE bank; USE bank;` — that's MySQL syntax left over from the original dataset scripts, not valid Postgres (`USE` doesn't exist in Postgres, and `CREATE DATABASE` can't run mid-script the way it's written here). Connect directly to the `scb_proj` database you just created and run the file anyway — psql will print a harmless error on those two lines and continue on to the actual `CREATE TABLE` statements, which land correctly in `scb_proj` since that's what you're connected to.

```bash
psql -U postgres -d scb_proj -f ../sql/schema.sql
psql -U postgres -d scb_proj -f ../sql/customers_inserts.sql
psql -U postgres -d scb_proj -f ../sql/accounts_inserts.sql
psql -U postgres -d scb_proj -f ../sql/cards_inserts.sql
psql -U postgres -d scb_proj -f ../sql/merchants_inserts.sql
psql -U postgres -d scb_proj -f ../sql/branches_inserts.sql
psql -U postgres -d scb_proj -f ../sql/loans_inserts.sql
psql -U postgres -d scb_proj -f ../sql/transactions_inserts.sql
```

**2. Configure your dbt profile** at `~/.dbt/profiles.yml`:

```yaml
scb_project:
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5432
      user: <your_user>
      pass: <your_password>
      dbname: scb_proj
      schema: dbt_saif   # arbitrary — every layer sets its own schema explicitly
      threads: 4
  target: dev
```

This file is never committed — each teammate/environment needs their own, pointing at their own Postgres instance.

**3. Verify the connection:**

```bash
dbt debug
```

**4. Build everything, in order** (each layer depends on the previous one):

```bash
dbt build --select bronze
dbt build --select silver
dbt build --select gold
dbt build --select reporting
```

Or simply `dbt build` to run the whole DAG plus all tests in dependency order in one go.

---

## Known limitations

- **Static dataset**: this is a one-time load, not a live/streaming source. The SCD2 machinery in Gold is correctly implemented but won't produce a second version of any row unless the pipeline is rerun against genuinely changed source data.
- **No true balance history**: `fact_account_balance` reflects only the current balance; cohort/trend questions about deposits are answered as "cohort opened in month X has $Y today," not a real time series.
- **Temporal inconsistency is expected**: because `open_date`, `start_date`, and `transaction_date` were generated independently per entity in the source data, the three cross-entity date tests will always report violations (roughly 4% of accounts, 4% of loans, 50% of transactions). This is flagged as `warn`, not `error` — it's a documented dataset characteristic, not a bug to chase.
- **Branches are an orphan dimension**: no FK exists from `branches` to any other entity in the source schema, so no fact table references it.

---

## Naming conventions

| Element | Convention | Example |
|---|---|---|
| Bronze/Silver/Gold/Reporting tables | `<layer>__<entity>` | `bronze__customers`, `silver__hub_customer`, `gold__dim_customer` |
| Data Vault hash keys | `hk_<entity>` | `hk_customer` |
| Gold durable keys | `<entity>_hub_key` | `customer_hub_key` |
| Gold surrogate keys | `<entity>_key` | `customer_key` (version-level, don't join facts on this) |
| dbt model files | `<layer>__<entity>.sql`, one model per file | `silver__sat_customer.sql` |
