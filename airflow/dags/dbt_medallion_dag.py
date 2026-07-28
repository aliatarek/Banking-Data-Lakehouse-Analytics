"""Bronze -> Silver -> Gold medallion pipeline.

A source-availability check runs first (a health check, not a transformation),
then Cosmos renders the entire dbt project's ref()/source() graph as native
Airflow tasks — bronze, silver, and gold models plus their dbt tests all show
up individually in the Airflow UI graph view. No SQL lives in this file.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta
from pathlib import Path

from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.sdk import DAG, task
from callbacks import log_failure, log_success
from cosmos import (
    DbtTaskGroup,
    ExecutionConfig,
    ExecutionMode,
    ProfileConfig,
    ProjectConfig,
)

DBT_PROJECT_DIR = Path(os.environ.get("DBT_PROJECT_DIR", "/opt/airflow/dbt"))
SOURCE_CONN_ID = "source_postgres"
SOURCE_TABLES = ["customers", "accounts", "cards", "merchants", "branches", "loans", "transactions"]

default_args = {
    "owner": "data-platform",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,
    "on_failure_callback": log_failure,
    "on_success_callback": log_success,
}

project_config = ProjectConfig(dbt_project_path=DBT_PROJECT_DIR)

profile_config = ProfileConfig(
    profile_name="scb_project",
    target_name="prod",
    profiles_yml_filepath=DBT_PROJECT_DIR / "profiles.yml",
)

execution_config = ExecutionConfig(execution_mode=ExecutionMode.LOCAL)

with DAG(
    dag_id="dbt_medallion_pipeline",
    description="Bronze -> Silver -> Gold medallion pipeline via dbt + Cosmos",
    start_date=datetime(2026, 1, 1),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["dbt", "medallion", "cosmos"],
) as dag:

    @task(task_id="check_source_availability")
    def check_source_availability() -> None:
        """Fail fast if the source Postgres schema is unreachable or empty."""
        hook = PostgresHook(postgres_conn_id=SOURCE_CONN_ID)
        for table in SOURCE_TABLES:
            row = hook.get_first(f"SELECT COUNT(*) FROM public.{table}")
            if row is None or row[0] == 0:
                raise ValueError(f"Source table public.{table} is unreachable or empty.")

    source_check = check_source_availability()

    dbt_medallion = DbtTaskGroup(
        group_id="dbt_medallion",
        project_config=project_config,
        profile_config=profile_config,
        execution_config=execution_config,
    )

    @task(task_id="pipeline_complete")
    def pipeline_complete() -> None:
        print("Bronze -> Silver -> Gold pipeline completed successfully.")

    source_check >> dbt_medallion >> pipeline_complete()
