# Banking Data Lakehouse & Analytics

A production-style DataOps platform for a synthetic retail banking dataset (1.26M+ records across 7 source tables): Airflow orchestrates dbt (via Astronomer Cosmos) through a Bronze → Silver → Gold → Reporting medallion pipeline on Postgres, and Superset visualizes the Reporting layer.

```
Postgres (Railway)  →  Bronze (raw)  →  Silver (Data Vault: hubs/links/satellites)  →  Gold (star schema)  →  Reporting (BI-shaped tables)  →  Superset
                              orchestrated end-to-end by Airflow + Cosmos
```

## Stack

| Layer         | Tool                                    |
|---------------|------------------------------------------|
| Orchestration | Apache Airflow 3.x (CeleryExecutor)      |
| Transformation| dbt Core + dbt-postgres                  |
| dbt ↔ Airflow | Astronomer Cosmos (no BashOperators)     |
| Warehouse     | PostgreSQL, hosted on Railway            |
| BI            | Apache Superset                          |
| Runtime       | Docker Compose                           |

## Data source

Synthetic retail banking dataset (Kaggle: `akrambelha/synthetic-banking-dataset-csv-sql-sqlite`): `customers`, `accounts`, `cards`, `merchants`, `branches`, `loans`, `transactions`, loaded into the `public` schema of the Railway Postgres instance before dbt touches anything.

Known gaps in the source data (not fabricated anywhere downstream — see [Known limitations](#known-limitations)):
- No FK linking `branches` to accounts/transactions — orphan dimension
- No `transaction_type` (can't distinguish debit/credit)
- No `loan_status`/repayment tracking
- No customer demographics beyond city/credit_score
- No `account_status`
- `open_date`, `start_date`, and `transaction_date` were generated independently of `created_at` per entity, so a meaningful fraction of rows have a "child" date earlier than its "parent" date (see the warn-severity tests)

## Architecture

- **Source**: the OLTP tables live in the `public` schema of the same Railway Postgres instance — there's no separate ingestion system to poll.
- **Bronze** (`dbt/models/bronze`): 1:1 passthrough tables, no transformation, tagged with `_loaded_at`/`_source`.
- **Silver** (`dbt/models/silver`): a Data Vault 2.0 model — hubs (business keys), links (relationships), satellites (attributes + a `_is_valid` flag per business rule). Invalid rows are non-blocking and surfaced in `silver__quarantine`.
- **Gold** (`dbt/models/gold`): a Kimball star schema built from the *latest valid* satellite record per entity — SCD Type 2 dimensions (customer, account, card, merchant, branch, date) and facts (transactions, loans, account balances). See the full column reference in [`dbt/star_schema_data_dictionary.md`](dbt/star_schema_data_dictionary.md).
- **Reporting** (`dbt/models/reporting`): one flat, pre-aggregated table per BI chart/question, sitting on top of Gold so dashboard tools don't need to join or compute KPIs themselves. See [`dbt/models/reporting/REPORTING_CHART_GUIDE.md`](dbt/models/reporting/REPORTING_CHART_GUIDE.md) for the full chart-to-dataset mapping.
- **Airflow** (`airflow/dags/dbt_medallion_dag.py`): one DAG — a source-availability health check, then the entire dbt project rendered as native Airflow tasks by Cosmos (bronze → silver → gold → reporting, dbt tests included), then a completion marker. No SQL lives in the DAG.
- **Superset**: connects directly to the Reporting schema on Railway; a bootstrap script auto-registers that connection and a starter dashboard on first boot.

## Testing

166 dbt tests across all four layers:

- Structural: `unique`/`not_null` on every hash key and business key, `relationships` on every FK, `accepted_values` on categoricals (`account_type`, `card_type`, `credit_tier`).
- Custom generic tests (`dbt/tests/generic/`): `valid_email`, `not_in_future`, `positive_value`, `in_range` (optional upper bound), `not_empty_string`, `single_current_version` (SCD2 invariant: exactly one `is_current` row per hub key).
- Singular cross-entity tests (`dbt/tests/`): account/loan open dates vs. customer creation date, transaction date vs. account open date — configured `severity: warn` since these fail against a real, unfixable characteristic of the synthetic data (see [Known limitations](#known-limitations)), not a modeling bug.

Run everything with `dbt test` (or `dbt build` to run models + tests together).

## Repository layout

```
airflow/          Custom Airflow image (Dockerfile), DAGs, plugins
dbt/              dbt project — models/{bronze,silver,gold,reporting}, macros, tests, profiles.yml
superset/         Custom Superset image (Dockerfile), bootstrap script, config
scripts/          Shared helper scripts (platform-db init SQL)
EDA/              Exploratory data analysis notebook
docker-compose.yml
.env.example
requirements.txt  Local-only deps for running `dbt` from your own machine
```

## Prerequisites

- Docker + Docker Compose
- **~6 GB free disk** (Airflow image ~2.3 GB, Superset image ~1 GB, plus Postgres/Redis volumes and container logs)
- Network access to your Railway Postgres instance

## Setup

1. `cp .env.example .env` and fill in:
   - `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD` — your Railway Postgres credentials.
   - `PLATFORM_DB_PASSWORD`, `AIRFLOW__CORE__FERNET_KEY`, `AIRFLOW__WEBSERVER__SECRET_KEY`, `SUPERSET_SECRET_KEY` — generate with the commands noted inline in `.env.example`.
   - Admin usernames/passwords for Airflow and Superset.
   - On Linux, also set `AIRFLOW_UID` to your own user ID (`echo AIRFLOW_UID=$(id -u) >> .env`) so the bind-mounted `airflow/dags`, `airflow/plugins`, and `dbt/` folders stay writable/readable by the container.
2. `docker compose up` (add `-d` to detach). By default this **builds both images locally** from the Dockerfiles — no registry needed. First boot builds images and runs migrations — give it a few minutes.
   - Prebuilt images are also published at [`mo4222/banking-airflow`](https://hub.docker.com/r/mo4222/banking-airflow) and [`mo4222/banking-superset`](https://hub.docker.com/r/mo4222/banking-superset). To use those instead of building locally, run `docker compose pull` before `docker compose up` (or `docker compose up --pull always`).
3. Airflow UI: http://localhost:8080 (login with `_AIRFLOW_WWW_USER_USERNAME` / `_AIRFLOW_WWW_USER_PASSWORD`). Unpause and trigger `dbt_medallion_pipeline`.
4. Superset UI: http://localhost:8088 (login with `SUPERSET_ADMIN_USERNAME` / `SUPERSET_ADMIN_PASSWORD`). The "Gold Analytics (Railway Postgres)" connection and the "Banking Gold Layer - Overview" dashboard are created automatically on first boot.
5. Optional: `docker compose --profile flower up` also starts Flower (Celery monitoring) on http://localhost:5555.

Nothing runs locally besides the containers themselves — Airflow, dbt, and Superset all read/write the same Railway Postgres instance; Airflow's own internal metadata (task state, users, connections) lives in a small local `platform-db` container, per-teammate. Superset's metadata (dashboards, charts, users) is instead stored on a shared Railway database (`superset_metadata`) so it stays in sync across the team — see the note below.

## Running dbt without Docker

```
pip install -r requirements.txt
export $(cat .env | xargs)   # or use direnv / your own tool
export DBT_PROFILES_DIR=dbt
cd dbt && dbt build
```

## Known limitations

- **Static dataset**: this is a one-time load, not a live/streaming source. The SCD2 machinery in Gold is correctly implemented but won't produce a second version of any row unless the pipeline is rerun against genuinely changed source data.
- **No true balance history**: `fact_account_balance` reflects only the current balance; cohort/trend questions about deposits are answered as "cohort opened in month X has $Y today," not a real time series.
- **Temporal inconsistency is expected**: because `open_date`, `start_date`, and `transaction_date` were generated independently per entity in the source data, the three cross-entity date tests will always report violations (roughly 4% of accounts, 4% of loans, 50% of transactions). This is flagged as `warn`, not `error` — it's a documented dataset characteristic, not a bug to chase.
- **Branches are an orphan dimension**: no FK exists from `branches` to any other entity in the source schema, so no fact table references it.

## Naming conventions

| Element | Convention | Example |
|---|---|---|
| Bronze/Silver/Gold/Reporting tables | `<layer>__<entity>` | `bronze__customers`, `silver__hub_customer`, `gold__dim_customer` |
| Data Vault hash keys | `hk_<entity>` | `hk_customer` |
| Gold durable keys | `<entity>_hub_key` | `customer_hub_key` |
| Gold surrogate keys | `<entity>_key` | `customer_key` (version-level, don't join facts on this) |
| dbt model files | `<layer>__<entity>.sql`, one model per file | `silver__sat_customer.sql` |

## Sharing state across the team

- **Data** (Bronze/Silver/Gold/Reporting tables) and **Airflow DAG code / dbt models** are shared automatically — everyone's containers point at the same Railway Postgres instance, and code syncs via git.
- **Superset dashboards/charts/users** are shared live — its metadata store lives on the same Railway project (`superset_metadata`), not a per-teammate local database.
- **Airflow's own run history/users/connections** stay per-teammate (local `platform-db`) — each teammate's scheduler/worker talks to its own local Redis broker, so sharing that metadata DB across independently-run schedulers would cause races on task-instance state.
