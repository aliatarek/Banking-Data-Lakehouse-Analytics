"""Imports teammate-exported Superset bundles (mounted from
``superset_dashboard/`` at the repo root). A bundle can be a single chart
export or a full-instance export containing multiple dashboards/charts/
datasets/databases (as Superset's "Export all" produces) — either shape is
handled the same way, since Superset's importer matches every object by
UUID with ``overwrite=True``: known objects (e.g. the team's "Banking-
Analytics" dashboard) update in place on every re-drop, and anything new
(e.g. Superset's own bundled sample dashboards, if a teammate drops a full-
instance export) is just created as its own separate dashboard — harmless
clutter, never merged into the team's dashboard.

Safe to re-run on every container start and on every poll cycle.
"""

from __future__ import annotations

import glob
import logging
import os
from zipfile import ZipFile

import yaml

logger = logging.getLogger("superset_bootstrap")

EXPORTS_DIR = "/app/superset_dashboard"

# Superset ships a built-in "examples" database (its own sample dashboards'
# data source) whose connection (typically a sibling "db" host from the
# exporting teammate's own local docker-compose) doesn't exist in this
# project's environment. A full-instance export bundles it and Superset's 9
# sample dashboards alongside real work; drop all of it before importing so
# the import doesn't fail trying to connect to an unreachable database.
SAMPLE_DATABASE_NAMES = {"examples"}


def _drop_sample_data(contents: dict[str, str]) -> dict[str, str]:
    excluded_db_uuids = set()
    for key, raw in contents.items():
        if key.startswith("databases/") and key.endswith(".yaml"):
            data = yaml.safe_load(raw)
            if data.get("database_name") in SAMPLE_DATABASE_NAMES:
                excluded_db_uuids.add(data["uuid"])

    excluded_dataset_uuids = set()
    for key in list(contents.keys()):
        if key.startswith("datasets/") and key.endswith(".yaml"):
            data = yaml.safe_load(contents[key])
            if data.get("database_uuid") in excluded_db_uuids:
                excluded_dataset_uuids.add(data["uuid"])
                del contents[key]

    for key in list(contents.keys()):
        if key.startswith("databases/") and key.endswith(".yaml"):
            data = yaml.safe_load(contents[key])
            if data["uuid"] in excluded_db_uuids:
                del contents[key]

    excluded_chart_uuids = set()
    for key in list(contents.keys()):
        if key.startswith("charts/") and key.endswith(".yaml"):
            data = yaml.safe_load(contents[key])
            if data.get("dataset_uuid") in excluded_dataset_uuids:
                excluded_chart_uuids.add(data["uuid"])
                del contents[key]

    for key in list(contents.keys()):
        if key.startswith("dashboards/") and key.endswith(".yaml"):
            data = yaml.safe_load(contents[key])
            position_uuids = {
                node.get("meta", {}).get("uuid")
                for node in (data.get("position") or {}).values()
                if isinstance(node, dict) and node.get("type") == "CHART"
            }
            if position_uuids and position_uuids <= excluded_chart_uuids:
                del contents[key]

    return contents


def _strip_incompatible_fields(contents: dict[str, str]) -> dict[str, str]:
    """Some exports are made with a newer Superset version whose YAML schema
    includes fields this version's importer rejects as unknown. Drop them
    rather than fail the whole import."""
    for key in list(contents.keys()):
        if key.startswith("datasets/") and key.endswith(".yaml"):
            data = yaml.safe_load(contents[key])
            for col in data.get("columns") or []:
                col.pop("datetime_format", None)
            data.pop("currency_code_column", None)
            data.pop("folders", None)
            contents[key] = yaml.dump(data)
        if key.startswith("databases/") and key.endswith(".yaml"):
            data = yaml.safe_load(contents[key])
            data.pop("impersonate_user", None)
            data.pop("configuration_method", None)
            contents[key] = yaml.dump(data)
        if key.startswith("dashboards/") and key.endswith(".yaml"):
            data = yaml.safe_load(contents[key])
            data.pop("theme_uuid", None)
            contents[key] = yaml.dump(data)
    return contents


def _import_one(path: str, db_password: str) -> None:
    from superset.commands.dashboard.importers.dispatcher import ImportDashboardsCommand
    from superset.commands.importers.v1.utils import get_contents_from_bundle

    with ZipFile(path) as bundle:
        contents = get_contents_from_bundle(bundle)
    contents = _drop_sample_data(contents)
    contents = _strip_incompatible_fields(contents)

    password_keys = [k for k in contents if k.startswith("databases/")]
    passwords = {k: db_password for k in password_keys}

    command = ImportDashboardsCommand(contents, passwords=passwords, overwrite=True)
    command.run()
    logger.info("Imported bundle: %s", os.path.basename(path))


def import_all() -> None:
    """Import every .zip in EXPORTS_DIR."""
    from flask import g
    from flask_appbuilder.security.sqla.models import User
    from superset import db as flask_db

    if g.get("user") is None:
        g.user = flask_db.session.query(User).filter_by(username=os.environ["SUPERSET_ADMIN_USERNAME"]).one()

    db_password = os.environ["DB_PASSWORD"]
    for path in sorted(glob.glob(os.path.join(EXPORTS_DIR, "*.zip"))):
        try:
            _import_one(path, db_password)
        except Exception:
            logger.exception("Failed to import bundle: %s", os.path.basename(path))


if __name__ == "__main__":
    from superset.app import create_app

    app = create_app()
    with app.app_context(), app.test_request_context():
        import_all()
