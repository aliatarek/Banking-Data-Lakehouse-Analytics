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
superset/           Custom Superset image (Dockerfile), bootstrap + auto-chart-discovery scripts, config
scripts/            Shared helper scripts (platform-db init SQL)
EDA/                Exploratory data analysis notebook
docker-compose.yml
.env.example
requirements.txt    Local-only deps for running `dbt` from your own machine
```

## Prerequisites

- Docker + Docker Compose
- **~3 GB free disk** (Airflow image ~1.13 GB, Superset image ~955 MB, plus Postgres/Redis volumes and container logs)
- Network access to the shared team Railway Postgres instance (credentials from a teammate — see [Setup](#setup-step-by-step))

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

**Every start (not just the first) takes a while, and that's expected**: Superset re-syncs its role/permission definitions on every boot — restart included — and each of those steps is a real network round trip to the shared Railway instance, so even a plain `docker compose restart superset` commonly takes 5–10 minutes before it reports healthy. First boot is slower still (schema migrations + the initial full pass over every `reporting` table), 15–40 minutes depending on network conditions. Watch progress with:

```bash
docker compose logs -f superset
docker compose logs -f airflow-api-server
```

**3. Access Airflow** — http://localhost:8080

Log in with `_AIRFLOW_WWW_USER_USERNAME` / `_AIRFLOW_WWW_USER_PASSWORD`. Unpause and trigger the `dbt_medallion_pipeline` DAG to run the full bronze→silver→gold→reporting pipeline against Railway.

**4. Access Superset and the dashboard** — http://localhost:8088

Log in with `SUPERSET_ADMIN_USERNAME` / `SUPERSET_ADMIN_PASSWORD`. On first boot this automatically creates:
- A **"Gold Analytics (Railway Postgres)"** database connection.
- A dataset + a default chart for **every table in the `reporting` schema** — no manual chart-building, no exporting/importing anything. A background discovery process (`superset/sync_reporting_tables.py`) introspects each table's shape and picks a sensible visualization: a one-row table becomes a KPI tile, a table with a date/month/year column plus a numeric column becomes a time-series line chart, anything else becomes a plain table view.
- All of these charts are attached to one dashboard: **"Banking Data Lakehouse Analytics"** (find it under Dashboards).

**Adding a new report later:** just add a `.sql` model to `dbt/models/reporting/` — the normal dbt workflow, no Superset knowledge required — and push. Once `dbt build` runs (the daily Airflow schedule, or a manual run — see [Common commands](#common-commands)) and the new table exists in Railway's `reporting` schema, any Superset container already running picks it up automatically within ~60 seconds and adds a default chart to the shared dashboard — no restart, no command. Since Superset's metadata lives on Railway, not per-teammate, it becomes visible to the whole team immediately once one running instance has processed it. Want something nicer than the auto-generated default? Build a better chart for that same table in Superset's UI — it won't be touched or duplicated, since the discovery process skips any table that already has a chart.

See [Common commands](#common-commands) below for logs, shells, rebuilding, and stopping — including the optional Flower (Celery monitoring) profile.

**5. Verify the auto-chart pipeline end to end** (optional, but a good way to confirm your setup actually works):

1. Add a throwaway model, e.g. `dbt/models/reporting/reporting__test_my_first_report.sql`:
   ```sql
   select
       date_trunc('month', created_date)::date as signup_month,
       count(*) as customer_count
   from {{ ref('gold__dim_customer') }}
   group by 1
   ```
2. Materialize it without waiting for the daily schedule:
   ```bash
   docker compose exec -T -e DBT_PROFILES_DIR=/opt/airflow/dbt airflow-api-server bash -c "cd /opt/airflow/dbt && dbt build --select reporting__test_my_first_report"
   ```
3. Watch `docker compose logs -f superset` — within ~60 seconds you should see `Auto-created chart for new reporting table: reporting__test_my_first_report (echarts_timeseries_line)` followed by `Synced dashboard: ... (N charts)`.
4. Confirm it in the browser: Dashboards → Banking Data Lakehouse Analytics.
5. Clean up afterward — delete the `.sql` file, then remove the dataset/chart/table so no test cruft lingers:
   ```bash
   rm dbt/models/reporting/reporting__test_my_first_report.sql
   docker exec banking-data-lakehouse-analytics-superset-1 python3 -c "
   from superset.app import create_app
   app = create_app()
   with app.app_context():
       from superset.connectors.sqla.models import SqlaTable
       from superset.models.slice import Slice
       from superset import db as flask_db
       ds = flask_db.session.query(SqlaTable).filter_by(table_name='reporting__test_my_first_report').first()
       if ds:
           chart = flask_db.session.query(Slice).filter_by(slice_name='Test My First Report').first()
           if chart: flask_db.session.delete(chart)
           flask_db.session.delete(ds)
           flask_db.session.commit()
   "
   set -a; source .env; set +a
   PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c 'drop table if exists reporting.reporting__test_my_first_report;'
   ```

---

Nothing runs locally besides the containers themselves — Airflow, dbt, and Superset all read/write the same Railway Postgres instance; Airflow's own internal metadata (task state, users, connections) lives in a small local `platform-db` container, per-teammate. Superset's metadata (dashboards, charts, users) is instead stored on a shared Railway database (`superset_metadata`) so it stays in sync across the team — see [Sharing state across the team](#sharing-state-across-the-team).

## Common commands

Everything below assumes you're in the repo root, where `docker-compose.yml` lives.

**Starting**
```bash
docker compose pull              # fetch the prebuilt mo4222/banking-airflow and mo4222/banking-superset images
docker compose up -d             # start everything, detached
docker compose up -d superset    # start (or recreate) just one service
```

**Checking status and logs**
```bash
docker compose ps                       # health/status of every container
docker compose logs -f superset         # follow logs for one service (Ctrl+C to stop following)
docker compose logs --tail 100 airflow-api-server
```

**Getting a shell inside a container**
```bash
docker compose exec -it airflow-api-server bash
docker compose exec -it superset bash
```

**Rebuilding after changing code** (`airflow/` or `superset/` — Dockerfiles COPY these in at build time, so edits alone don't take effect until rebuilt):
```bash
docker compose up -d --build airflow-api-server airflow-scheduler airflow-worker airflow-triggerer airflow-dag-processor
docker compose up -d --build superset
```

**Running dbt manually** (e.g. to pick up new model changes without waiting on the Airflow DAG):
```bash
docker compose exec -T -e DBT_PROFILES_DIR=/opt/airflow/dbt airflow-api-server bash -c "cd /opt/airflow/dbt && dbt build"
# if a build fails partway through, re-run just the failed/skipped nodes:
docker compose exec -T -e DBT_PROFILES_DIR=/opt/airflow/dbt airflow-api-server bash -c "cd /opt/airflow/dbt && dbt retry"
```

**Restarting a single service** (without a rebuild):
```bash
docker compose restart superset
```

**Stopping**
```bash
docker compose stop                     # stop containers, keep them (and volumes) around to resume later
docker compose down                     # stop + remove containers and the network, but keep volumes
                                         # (platform-db data, Airflow logs, Superset home persist — `docker compose up -d` picks up where you left off)
docker compose down -v                  # also delete volumes — full local reset, next boot starts from scratch
                                         # (safe: Railway data, the reporting schema, and Superset's dashboards/charts
                                         # all live on the shared Railway instance, not in these local volumes)
```

**Optional: Flower (Celery monitoring)**
```bash
docker compose --profile flower up
```

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
- **New reporting tables get a chart automatically**: push a `.sql` model to `dbt/models/reporting/`, and once it's materialized (daily schedule or a manual `dbt build`) any running Superset container discovers it and adds a default chart within ~60 seconds — no restart, no manual step — see [Setup step 4](#setup-step-by-step). `git pull` and running `dbt build` stay manual/reviewed steps; nothing auto-fetches or auto-executes pushed code unreviewed.
- **Airflow's own run history/users/connections** stay per-teammate (local `platform-db`) — each teammate's scheduler/worker talks to its own local Redis broker, so sharing that metadata DB across independently-run schedulers would cause races on task-instance state.
