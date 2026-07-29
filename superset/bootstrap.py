"""Idempotent first-boot setup: registers the Railway Postgres connection, the
Reporting-layer datasets, and a small starter dashboard. Safe to re-run on every
container start — every step checks for an existing row before creating one.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time

from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError

logger = logging.getLogger("superset_bootstrap")
logging.basicConfig(level=logging.INFO)

GOLD_DATABASE_NAME = "Gold Analytics (Railway Postgres)"
DASHBOARD_TITLE = "Banking Data Lakehouse Analytics"
DASHBOARD_SLUG = "banking-data-lakehouse-analytics"


def wait_for_metadata_db(max_attempts: int = 30, delay_seconds: int = 2) -> None:
    uri = os.environ["SUPERSET_DATABASE_URI"]
    engine = create_engine(uri)
    for attempt in range(1, max_attempts + 1):
        try:
            with engine.connect():
                logger.info("Metadata database is reachable.")
                return
        except OperationalError:
            logger.info("Waiting for metadata database (%s/%s)...", attempt, max_attempts)
            time.sleep(delay_seconds)
    raise SystemExit("Metadata database never became reachable.")


def gold_sqlalchemy_uri() -> str:
    return (
        f"postgresql+psycopg2://{os.environ['DB_USER']}:{os.environ['DB_PASSWORD']}"
        f"@{os.environ['DB_HOST']}:{os.environ['DB_PORT']}/{os.environ['DB_NAME']}"
    )


def get_or_create_database(db_session, Database):
    database = db_session.query(Database).filter_by(database_name=GOLD_DATABASE_NAME).first()
    if database:
        return database
    database = Database(database_name=GOLD_DATABASE_NAME, sqlalchemy_uri=gold_sqlalchemy_uri())
    db_session.add(database)
    db_session.commit()
    logger.info("Created database connection: %s", GOLD_DATABASE_NAME)
    return database


def get_or_create_dataset(db_session, SqlaTable, database, table_name: str, schema: str = "reporting"):
    dataset = (
        db_session.query(SqlaTable)
        .filter_by(table_name=table_name, schema=schema, database_id=database.id)
        .first()
    )
    if dataset:
        return dataset
    dataset = SqlaTable(table_name=table_name, schema=schema, database=database)
    db_session.add(dataset)
    db_session.commit()
    dataset.fetch_metadata()
    db_session.commit()
    logger.info("Created dataset: %s.%s", schema, table_name)
    return dataset


def get_or_create_chart(db_session, Slice, slice_name: str, dataset, viz_type: str, params: dict):
    chart = db_session.query(Slice).filter_by(slice_name=slice_name).first()
    if chart:
        return chart
    params = {**params, "datasource": f"{dataset.id}__table", "viz_type": viz_type}
    chart = Slice(
        slice_name=slice_name,
        viz_type=viz_type,
        datasource_id=dataset.id,
        datasource_type="table",
        params=json.dumps(params),
    )
    db_session.add(chart)
    db_session.commit()
    logger.info("Created chart: %s", slice_name)
    return chart


def build_position_json(charts: list) -> str:
    position = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "GRID_ID": {"type": "GRID", "id": "GRID_ID", "children": [], "parents": ["ROOT_ID"]},
    }
    for index, chart in enumerate(charts):
        chart_holder_id = f"CHART-{chart.id}"
        row_id = f"ROW-{index}"
        position[row_id] = {
            "type": "ROW",
            "id": row_id,
            "children": [chart_holder_id],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        }
        position[chart_holder_id] = {
            "type": "CHART",
            "id": chart_holder_id,
            "children": [],
            "parents": ["ROOT_ID", "GRID_ID", row_id],
            "meta": {"chartId": chart.id, "width": 4, "height": 50, "sliceName": chart.slice_name},
        }
        position["GRID_ID"]["children"].append(row_id)
    position["DASHBOARD_CHART_TYPE"] = "CHART"
    return json.dumps(position)


def get_or_create_dashboard(db_session, Dashboard, charts: list):
    dashboard = db_session.query(Dashboard).filter_by(slug=DASHBOARD_SLUG).first()
    if dashboard:
        dashboard.slices = charts
        dashboard.position_json = build_position_json(charts)
        db_session.commit()
        logger.info("Synced dashboard: %s (%d charts)", DASHBOARD_TITLE, len(charts))
        return dashboard
    dashboard = Dashboard(
        dashboard_title=DASHBOARD_TITLE,
        slug=DASHBOARD_SLUG,
        published=True,
        position_json=build_position_json(charts),
    )
    dashboard.slices = charts
    db_session.add(dashboard)
    db_session.commit()
    logger.info("Created dashboard: %s", DASHBOARD_TITLE)
    return dashboard


def bootstrap_assets() -> None:
    from superset.app import create_app

    app = create_app()
    with app.app_context():
        from superset import db as flask_db
        from superset.connectors.sqla.models import SqlaTable
        from superset.models.core import Database
        from superset.models.dashboard import Dashboard
        from superset.models.slice import Slice

        db_session = flask_db.session

        database = get_or_create_database(db_session, Database)

        customer_kpis = get_or_create_dataset(db_session, SqlaTable, database, "reporting__customer_kpis")
        monthly_txn = get_or_create_dataset(db_session, SqlaTable, database, "reporting__transaction_monthly_summary")
        balance_summary = get_or_create_dataset(db_session, SqlaTable, database, "reporting__customer_balance_summary")
        monthly_growth = get_or_create_dataset(db_session, SqlaTable, database, "reporting__monthly_customer_growth")

        def kpi_metric(column_name: str, label: str) -> dict:
            return {
                "expressionType": "SIMPLE",
                "column": {"column_name": column_name},
                "aggregate": "MAX",
                "label": label,
            }

        total_volume_metric = kpi_metric("total_transaction_volume_usd", "Total Transaction Volume (USD)")

        chart_total = get_or_create_chart(
            db_session,
            Slice,
            "Total Transaction Amount",
            customer_kpis,
            "big_number_total",
            {"metric": total_volume_metric, "adhoc_filters": [], "time_range": "No filter"},
        )

        chart_total_customers = get_or_create_chart(
            db_session,
            Slice,
            "Total Customers",
            customer_kpis,
            "big_number_total",
            {
                "metric": kpi_metric("total_customers", "Total Customers"),
                "adhoc_filters": [],
                "time_range": "No filter",
            },
        )

        chart_total_deposits = get_or_create_chart(
            db_session,
            Slice,
            "Total Deposits",
            customer_kpis,
            "big_number_total",
            {
                "metric": kpi_metric("total_deposits_usd", "Total Deposits (USD)"),
                "adhoc_filters": [],
                "time_range": "No filter",
            },
        )

        chart_total_loan_book = get_or_create_chart(
            db_session,
            Slice,
            "Total Loan Book",
            customer_kpis,
            "big_number_total",
            {
                "metric": kpi_metric("total_loan_book_usd", "Total Loan Book (USD)"),
                "adhoc_filters": [],
                "time_range": "No filter",
            },
        )

        chart_new_customers = get_or_create_chart(
            db_session,
            Slice,
            "New Customers per Month",
            monthly_growth,
            "echarts_timeseries_line",
            {
                "x_axis": "acquisition_month",
                "metrics": [
                    {
                        "expressionType": "SIMPLE",
                        "column": {"column_name": "new_customers"},
                        "aggregate": "SUM",
                        "label": "New Customers",
                    }
                ],
                "groupby": [],
                "adhoc_filters": [],
                "time_range": "No filter",
                "row_limit": 5000,
            },
        )

        chart_monthly = get_or_create_chart(
            db_session,
            Slice,
            "Monthly Transaction Volume",
            monthly_txn,
            "echarts_timeseries_line",
            {
                "x_axis": "transaction_month",
                "metrics": [
                    {
                        "expressionType": "SIMPLE",
                        "column": {"column_name": "total_transaction_volume_usd"},
                        "aggregate": "SUM",
                        "label": "Total Transaction Volume (USD)",
                    }
                ],
                "groupby": [],
                "adhoc_filters": [],
                "time_range": "No filter",
                "row_limit": 5000,
            },
        )

        chart_top_customers = get_or_create_chart(
            db_session,
            Slice,
            "Top Customers by Balance",
            balance_summary,
            "table",
            {
                "query_mode": "raw",
                "columns": ["customer_id", "first_name", "last_name", "city", "total_balance_usd"],
                "order_by_cols": ['["balance_rank", true]'],
                "row_limit": 10,
                "adhoc_filters": [],
                "time_range": "No filter",
            },
        )

        get_or_create_dashboard(
            db_session,
            Dashboard,
            [
                chart_total_customers,
                chart_total_deposits,
                chart_total_loan_book,
                chart_total,
                chart_new_customers,
                chart_monthly,
                chart_top_customers,
            ],
        )


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "bootstrap"
    if command == "wait-for-db":
        wait_for_metadata_db()
    else:
        bootstrap_assets()
