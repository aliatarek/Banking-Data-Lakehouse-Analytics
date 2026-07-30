"""Background poller: discovers new tables in the `reporting` dbt schema on
Railway and auto-creates a default chart for each one, with zero manual
Superset interaction. A teammate only has to add a `.sql` model to
dbt/models/reporting/ and push — once `dbt build` materializes it (daily
schedule or a manual run), this picks it up on its next cycle.

A dbt model defines data; a chart defines presentation. There's no way to
derive an ideal visualization from SQL alone, so this applies a simple,
deterministic heuristic instead of guessing at what a human would pick:
  - Exactly one row               -> big_number_total on the first numeric column.
  - Has a date/month/year column
    and a numeric column          -> time-series line chart.
  - Otherwise                     -> plain table view of every column.

Runs as a long-lived side process alongside gunicorn (started from
entrypoint.sh), polling every POLL_SECONDS. Never touches a table that
already has a Superset dataset, however that dataset was created (bootstrap.py,
a manual chart build, or a previous run of this script) — so it only ever
fills gaps, never duplicates or overrides existing work.
"""

from __future__ import annotations

import logging
import re
import time

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.types import Date, DateTime, Integer, Numeric, Float

logger = logging.getLogger("superset_bootstrap")

POLL_SECONDS = 60
REPORTING_SCHEMA = "reporting"
DATE_NAME_PATTERN = re.compile(r"(month|year|date)$", re.IGNORECASE)


def _list_reporting_tables(engine) -> set[str]:
    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "select table_name from information_schema.tables "
                "where table_schema = :schema"
            ),
            {"schema": REPORTING_SCHEMA},
        )
        return {row[0] for row in rows}


def _table_shape(engine, table_name: str) -> tuple[int, list[dict]]:
    inspector = inspect(engine)
    columns = inspector.get_columns(table_name, schema=REPORTING_SCHEMA)
    with engine.connect() as conn:
        row_count = conn.execute(
            text(f'select count(*) from "{REPORTING_SCHEMA}"."{table_name}"')
        ).scalar()
    return row_count, columns


def _is_numeric(col: dict) -> bool:
    return isinstance(col["type"], (Integer, Numeric, Float))


def _is_date_like(col: dict) -> bool:
    if isinstance(col["type"], (Date, DateTime)):
        return True
    return bool(DATE_NAME_PATTERN.search(col["name"]))


def _chart_title(table_name: str) -> str:
    name = table_name.removeprefix("reporting__")
    return name.replace("_", " ").title()


def _build_chart_config(table_name: str, row_count: int, columns: list[dict]) -> tuple[str, dict]:
    """Returns (viz_type, params) per the heuristic described in the module docstring."""
    numeric_cols = [c for c in columns if _is_numeric(c)]
    date_cols = [c for c in columns if _is_date_like(c)]

    if row_count == 1 and numeric_cols:
        metric_col = numeric_cols[0]["name"]
        return "big_number_total", {
            "metric": {
                "expressionType": "SIMPLE",
                "column": {"column_name": metric_col},
                "aggregate": "MAX",
                "label": metric_col,
            },
            "adhoc_filters": [],
            "time_range": "No filter",
        }

    if date_cols and numeric_cols:
        metric_col = numeric_cols[0]["name"]
        return "echarts_timeseries_line", {
            "x_axis": date_cols[0]["name"],
            "metrics": [
                {
                    "expressionType": "SIMPLE",
                    "column": {"column_name": metric_col},
                    "aggregate": "SUM",
                    "label": metric_col,
                }
            ],
            "groupby": [],
            "adhoc_filters": [],
            "time_range": "No filter",
            "row_limit": 5000,
        }

    params = {
        "query_mode": "raw",
        "columns": [c["name"] for c in columns],
        "row_limit": 50,
        "adhoc_filters": [],
        "time_range": "No filter",
    }
    if numeric_cols:
        params["order_by_cols"] = [f'["{numeric_cols[0]["name"]}", false]']
    return "table", params


def _sync_new_tables() -> None:
    from bootstrap import (
        DASHBOARD_SLUG,
        gold_sqlalchemy_uri,
        get_or_create_chart,
        get_or_create_dashboard,
        get_or_create_dataset,
    )
    from superset import db as flask_db
    from superset.connectors.sqla.models import SqlaTable
    from superset.models.core import Database
    from superset.models.dashboard import Dashboard
    from superset.models.slice import Slice

    engine = create_engine(gold_sqlalchemy_uri())
    current_tables = _list_reporting_tables(engine)

    database = flask_db.session.query(Database).filter_by(
        database_name="Gold Analytics (Railway Postgres)"
    ).one_or_none()
    if database is None:
        logger.warning("Gold Analytics database connection not found yet; skipping this cycle.")
        return

    # Deliberately not scoped to this connection's database_id: a table can already
    # have a dataset/chart registered under a different Superset "Database" object
    # (e.g. the old zip-import connections), and that still counts as covered —
    # the underlying Railway table is the same regardless of which Superset
    # connection points at it.
    already_covered = {
        d.table_name
        for d in flask_db.session.query(SqlaTable).filter_by(schema=REPORTING_SCHEMA)
    }

    new_charts = []
    for table_name in sorted(current_tables - already_covered):
        try:
            row_count, columns = _table_shape(engine, table_name)
            viz_type, params = _build_chart_config(table_name, row_count, columns)
            dataset = get_or_create_dataset(flask_db.session, SqlaTable, database, table_name)
            chart = get_or_create_chart(
                flask_db.session, Slice, _chart_title(table_name), dataset, viz_type, params
            )
            new_charts.append(chart)
            logger.info("Auto-created chart for new reporting table: %s (%s)", table_name, viz_type)
        except Exception:
            logger.exception("Failed to auto-create a chart for %s", table_name)

    if not new_charts:
        return

    dashboard = flask_db.session.query(Dashboard).filter_by(slug=DASHBOARD_SLUG).one_or_none()
    if dashboard is None:
        logger.warning("Dashboard %s not found; run bootstrap.py first.", DASHBOARD_SLUG)
        return

    existing_ids = {s.id for s in dashboard.slices}
    all_charts = list(dashboard.slices) + [c for c in new_charts if c.id not in existing_ids]
    get_or_create_dashboard(flask_db.session, Dashboard, all_charts)


def watch() -> None:
    from superset.app import create_app

    app = create_app()
    logger.info("Reporting-table watcher started (poll every %ss).", POLL_SECONDS)

    while True:
        time.sleep(POLL_SECONDS)
        try:
            with app.app_context(), app.test_request_context():
                _sync_new_tables()
        except Exception:
            logger.exception("Reporting-table watcher cycle failed; will retry next cycle.")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    watch()
