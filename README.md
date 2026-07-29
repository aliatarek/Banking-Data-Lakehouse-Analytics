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

## Recent model changes

Changes made to `dbt/models/` during the Airflow/Superset integration, most recent first:

- **`credit_tier` bucket labels renamed** (`gold__dim_customer.sql`): `excellent/good/fair/poor/very_poor` → industry-standard `super_prime/prime/near_prime/subprime/deep_subprime`. Every reporting model that references `credit_tier` (`reporting__interest_rate_by_credit_tier`, `reporting__loan_penetration_by_credit_tier`, `reporting__customer_credit_mix_monthly`) was updated to match.
- **Fixed a join-key bug** in `reporting__interest_rate_by_credit_tier.sql`: the loan-to-customer join used the wrong column (`fl.hk_customer`, which doesn't exist on that table) — corrected to `fl.customer_hub_key`. Also added a missing `where is_current` filter so only the latest dimension version is counted.
- **Grain change**: `reporting__monthly_account_openings_by_type` → `reporting__yearly_account_openings_by_type` — account openings are now aggregated by year, not month.
- **New reporting layer** (`dbt/models/reporting/`): one flat, pre-aggregated table per BI chart, plus `REPORTING_CHART_GUIDE.md` (chart-to-dataset mapping) and `REPORTING_METRIC_CHEATSHEET.md` (which aggregate — `MAX`/`SUM`/`COUNT` — to use per dataset).
- **Performance fix in all 12 Silver hub/link models** (`dbt/models/silver/hubs/`, `dbt/models/silver/links/`): the incremental "skip already-loaded rows" check used `not in (select x from {{ this }})`, which Postgres can't safely turn into a hash anti-join once the target table has real data (NULL semantics make `NOT IN` unsafe to optimize) — it was falling back to an O(n²) per-row rescan. Against `silver__hub_transaction` (1M rows) this had a planner cost estimate of ~19.3 billion and never completed in practice. Rewritten as `not exists (select 1 from {{ this }} existing where existing.x = deduped.x)`, which Postgres plans as a proper Hash Anti Join (verified cost: ~311k). This affects every hub/link model, not just the one that hit the wall — all of them would have failed the same way on their next incremental run once populated.

## Testing

166 dbt tests across all four layers:

- Structural: `unique`/`not_null` on every hash key and business key, `relationships` on every FK, `accepted_values` on categoricals (`account_type`, `card_type`, `credit_tier`).
- Custom generic tests (`dbt/tests/generic/`): `valid_email`, `not_in_future`, `positive_value`, `in_range` (optional upper bound), `not_empty_string`, `single_current_version` (SCD2 invariant: exactly one `is_current` row per hub key).
- Singular cross-entity tests (`dbt/tests/`): account/loan open dates vs. customer creation date, transaction date vs. account open date — configured `severity: warn` since these fail against a real, unfixable characteristic of the synthetic data (see [Known limitations](#known-limitations)), not a modeling bug.

Run everything with `dbt test` (or `dbt build` to run models + tests together).

## Repository layout

```
airflow/            Custom Airflow image (Dockerfile), DAGs, plugins
dbt/                dbt project — models/{bronze,silver,gold,reporting}, macros, tests, profiles.yml
superset/           Custom Superset image (Dockerfile), bootstrap + chart-import scripts, config
dashboarding reports/  Superset chart exports (.zip) contributed by teammates, auto-imported on boot
scripts/            Shared helper scripts (platform-db init SQL)
EDA/                Exploratory data analysis notebook
docker-compose.yml
.env.example
requirements.txt    Local-only deps for running `dbt` from your own machine
```

## Prerequisites

- Docker + Docker Compose
- **~6 GB free disk** (Airflow image ~2.3 GB, Superset image ~1 GB, plus Postgres/Redis volumes and container logs)
- Network access to your Railway Postgres instance

## Setup: step-by-step

**1. Get the code and configure your environment**

```bash
git clone https://github.com/aliatarek/Banking-Data-Lakehouse-Analytics.git
cd Banking-Data-Lakehouse-Analytics
cp .env.example .env
```

Edit `.env` and fill in:
- `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD` — the shared Railway Postgres credentials (ask a teammate if you don't have these).
- `PLATFORM_DB_PASSWORD`, `AIRFLOW__CORE__FERNET_KEY`, `AIRFLOW__WEBSERVER__SECRET_KEY`, `SUPERSET_SECRET_KEY` — generate with the commands noted inline in `.env.example`.
- Admin usernames/passwords for Airflow and Superset (`_AIRFLOW_WWW_USER_*`, `SUPERSET_ADMIN_*`).
- **On Linux**, also set `AIRFLOW_UID` to your own user ID so the bind-mounted `airflow/dags`, `airflow/plugins`, and `dbt/` folders stay writable by the container:
  ```bash
  echo "AIRFLOW_UID=$(id -u)" >> .env
  ```

**2. Start everything**

```bash
docker compose pull   # use the prebuilt mo4222/banking-airflow and mo4222/banking-superset images
docker compose up -d
```

(Omit `docker compose pull` if you'd rather build both images locally from the Dockerfiles — no registry needed, just slower on first boot.)

**First boot takes a while and that's expected**: Airflow runs DB migrations, and Superset does a one-time migration against its metadata store followed by importing the teammate-exported charts — each step is a real network round trip to the shared Railway instance, so first startup can take 15–40 minutes depending on network conditions. Subsequent restarts are fast (migrations are already applied). Watch progress with:

```bash
docker compose logs -f superset
docker compose logs -f airflow-api-server
```

**3. Access Airflow** — http://localhost:8080

Log in with `_AIRFLOW_WWW_USER_USERNAME` / `_AIRFLOW_WWW_USER_PASSWORD`. Unpause and trigger the `dbt_medallion_pipeline` DAG to run the full bronze→silver→gold→reporting pipeline against Railway.

**4. Access Superset and the dashboard** — http://localhost:8088

Log in with `SUPERSET_ADMIN_USERNAME` / `SUPERSET_ADMIN_PASSWORD`. On first boot this automatically creates:
- A **"Gold Analytics (Railway Postgres)"** database connection and 4 reporting datasets, used by 7 starter charts (the 4 `reporting__customer_kpis` KPI tiles, monthly transaction volume, new customers per month, top customers by balance).
- 9 additional charts imported from teammates' own exports (`dashboarding reports/*.zip`) — card portfolio, credit risk, and transaction-activity charts.
- All 16 charts are attached to one dashboard: **"Banking Data Lakehouse Analytics"** (find it under Dashboards). No manual chart-building needed — everything is created for you.

**5. Optional: Flower (Celery monitoring)**

```bash
docker compose --profile flower up
```
Then visit http://localhost:5555.

---

Nothing runs locally besides the containers themselves — Airflow, dbt, and Superset all read/write the same Railway Postgres instance; Airflow's own internal metadata (task state, users, connections) lives in a small local `platform-db` container, per-teammate. Superset's metadata (dashboards, charts, users) is instead stored on a shared Railway database (`superset_metadata`) so it stays in sync across the team — see [Sharing state across the team](#sharing-state-across-the-team).

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
