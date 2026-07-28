# Banking Data Lakehouse & Analytics

A production-style DataOps platform for a synthetic banking dataset: Airflow orchestrates dbt (via Astronomer Cosmos) through a Bronze → Silver → Gold medallion pipeline on Postgres, and Superset visualizes the Gold layer.

```
Postgres (Railway)  →  Bronze (raw)  →  Silver (Data Vault: hubs/links/satellites)  →  Gold (star schema)  →  Superset
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

## Architecture

- **Source**: the OLTP tables (`customers`, `accounts`, `cards`, `merchants`, `branches`, `loans`, `transactions`) live in the `public` schema of the same Railway Postgres instance — there's no separate ingestion system to poll.
- **Bronze** (`dbt/models/bronze`): 1:1 passthrough tables, no transformation, tagged with `_loaded_at`/`_source`.
- **Silver** (`dbt/models/silver`): a Data Vault 2.0 model — hubs (business keys), links (relationships), satellites (attributes + a `_is_valid` flag per business rule). Invalid rows are non-blocking and surfaced in `silver__quarantine`.
- **Gold** (`dbt/models/gold`): a star schema built from the *latest valid* satellite record per entity — dimensions (customer, account, card, merchant, branch, date) and facts (transactions, loans, account balances).
- **Airflow** (`airflow/dags/dbt_medallion_dag.py`): one DAG — a source-availability health check, then the entire dbt project rendered as native Airflow tasks by Cosmos (bronze → silver → gold, dbt tests included), then a completion marker. No SQL lives in the DAG.
- **Superset**: connects directly to the Gold schema on Railway; a bootstrap script auto-registers that connection and a starter dashboard on first boot.

## Repository layout

```
airflow/          Custom Airflow image (Dockerfile), DAGs, plugins
dbt/              dbt project — models/{bronze,silver,gold}, macros, tests, profiles.yml
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

Nothing runs locally besides the containers themselves — Airflow, dbt, and Superset all read/write the same Railway Postgres instance; only Airflow's and Superset's own internal metadata (task state, users, dashboards) live in a small local `platform-db` container, kept separate from the business data.

## Running dbt without Docker

```
pip install -r requirements.txt
export $(cat .env | xargs)   # or use direnv / your own tool
export DBT_PROFILES_DIR=dbt
cd dbt && dbt build
```

## Notes

- `dim_branch` has no fact linkage — the source dataset has no FK from branches to accounts or transactions.
- Silver satellites are insert-only history; Gold dimensions collapse each hub/satellite pair to its latest **valid** row via `distinct on (hash_key) ... order by load_dts desc`.
- Three singular dbt tests (`tests/test_silver_sat_*.sql`) are `severity: warn` by design — they flag real data-quality findings in the source dataset (e.g. accounts opened before the owning customer existed) without blocking the pipeline.
