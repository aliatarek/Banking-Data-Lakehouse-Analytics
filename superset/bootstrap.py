"""Idempotent first-boot setup: registers the Railway Postgres connection so
teammates can pick reporting-schema tables when building charts in Superset's
UI. Safe to re-run on every container start — checks for an existing row
before creating one.

Chart/dashboard creation isn't handled here — the team's dashboard
("Banking-Analytics") is built directly in Superset's UI and shared live via
the Railway metadata DB, or reproduced on a fresh environment via
import_dashboard_exports.py against a teammate's exported .zip.
"""

from __future__ import annotations

import logging
import os
import sys
import time

from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError

logger = logging.getLogger("superset_bootstrap")
logging.basicConfig(level=logging.INFO)

GOLD_DATABASE_NAME = "Gold Analytics (Railway Postgres)"


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


def bootstrap_assets() -> None:
    from superset.app import create_app

    app = create_app()
    with app.app_context():
        from superset import db as flask_db
        from superset.models.core import Database

        db_session = flask_db.session

        get_or_create_database(db_session, Database)


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "bootstrap"
    if command == "wait-for-db":
        wait_for_metadata_db()
    else:
        bootstrap_assets()
