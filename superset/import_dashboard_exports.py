"""Imports teammate-exported Superset bundles (mounted from
``superset_dashboard/`` at the repo root). A bundle can be a single chart
export or a full-instance export containing multiple dashboards/charts/
datasets/databases (as Superset's "Export all" produces) — either shape is
handled the same way, since Superset's importer matches every object by
UUID with ``overwrite=True``: known objects update in place on every
re-drop, and anything new (e.g. Superset's own bundled sample dashboards, if
a teammate drops a full-instance export) is created as its own dashboard.

After importing, every dashboard is folded onto the one team dashboard
(TARGET_DASHBOARD_TITLE below) and removed — see
``_consolidate_into_target_dashboard``. So it doesn't matter what a dropped
export's own dashboard is named or which UUID it carries (a teammate
exporting a fresh, untitled dashboard of charts still ends up merged in);
the only thing that matters is which *charts* it brought.

Safe to re-run on every container start and on every poll cycle.
"""

from __future__ import annotations

import glob
import json
import logging
import os
from zipfile import ZipFile

import yaml

logger = logging.getLogger("superset_bootstrap")

EXPORTS_DIR = "/app/superset_dashboard"

# The one dashboard everything gets consolidated onto, regardless of what a
# dropped export's own dashboard is titled.
TARGET_DASHBOARD_TITLE = "Banking-Analytics"

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


def _build_position_json(charts: list) -> str:
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


def _consolidate_into_target_dashboard() -> None:
    """Fold every dashboard's charts onto TARGET_DASHBOARD_TITLE and delete
    the rest, so a dropped export's own dashboard title/UUID never matters."""
    from superset import db as flask_db
    from superset.models.dashboard import Dashboard

    session = flask_db.session
    all_dashboards = session.query(Dashboard).order_by(Dashboard.id).all()
    if not all_dashboards:
        return

    target = next((d for d in all_dashboards if d.dashboard_title == TARGET_DASHBOARD_TITLE), None)
    renamed = False
    if target is None:
        target = all_dashboards[0]
        logger.info("No dashboard named %r yet; promoting dashboard %d.", TARGET_DASHBOARD_TITLE, target.id)
        target.dashboard_title = TARGET_DASHBOARD_TITLE
        renamed = True

    others = [d for d in all_dashboards if d.id != target.id]
    if not others:
        if renamed:
            session.commit()
        return

    existing_ids = {s.id for s in target.slices}
    merged = list(target.slices)
    for other in others:
        for chart in other.slices:
            if chart.id not in existing_ids:
                merged.append(chart)
                existing_ids.add(chart.id)
        session.delete(other)

    target.slices = merged
    target.position_json = _build_position_json(merged)
    session.commit()
    logger.info(
        "Consolidated %d extra dashboard(s) into %r (%d chart(s) total).",
        len(others), TARGET_DASHBOARD_TITLE, len(merged),
    )


def import_all() -> None:
    """Import every .zip in EXPORTS_DIR, then consolidate onto one dashboard."""
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

    try:
        _consolidate_into_target_dashboard()
    except Exception:
        logger.exception("Failed to consolidate dashboards.")


if __name__ == "__main__":
    from superset.app import create_app

    app = create_app()
    with app.app_context(), app.test_request_context():
        import_all()
