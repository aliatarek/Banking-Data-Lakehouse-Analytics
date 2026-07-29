"""Imports teammate-exported Superset chart bundles (mounted from
``dashboarding reports/`` at the repo root) and attaches them to the shared
dashboard alongside the charts bootstrap.py manages directly.

Safe to re-run on every container start: Superset's importer matches
existing objects by UUID (``overwrite=True``), and this script always
recomputes the dashboard's full chart list and position_json rather than
appending blindly.
"""

from __future__ import annotations

import glob
import logging
import os
from zipfile import ZipFile

import yaml

logger = logging.getLogger("superset_bootstrap")

EXPORTS_DIR = "/app/dashboarding_reports"


def _strip_incompatible_fields(contents: dict[str, str]) -> dict[str, str]:
    """Some exports were made with a newer Superset version whose YAML
    schema includes fields this version's importer rejects as unknown.
    Drop them rather than fail the whole import."""
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
    return contents


def _import_one(path: str, db_password: str):
    from superset import db as flask_db
    from superset.commands.chart.importers.dispatcher import ImportChartsCommand
    from superset.commands.importers.v1.utils import get_contents_from_bundle
    from superset.models.slice import Slice

    with ZipFile(path) as bundle:
        contents = get_contents_from_bundle(bundle)
    contents = _strip_incompatible_fields(contents)

    password_key = next(k for k in contents if k.startswith("databases/"))
    chart_yaml_key = next(k for k in contents if k.startswith("charts/"))
    chart_uuid = yaml.safe_load(contents[chart_yaml_key])["uuid"]

    command = ImportChartsCommand(contents, passwords={password_key: db_password}, overwrite=True)
    command.run()
    logger.info("Imported chart export: %s", os.path.basename(path))
    return flask_db.session.query(Slice).filter_by(uuid=chart_uuid).one()


def import_and_attach(dashboard) -> None:
    """Import every .zip in EXPORTS_DIR and merge the resulting charts into
    the given Dashboard's chart list."""
    from bootstrap import build_position_json
    from superset import db as flask_db
    from flask import g
    from flask_appbuilder.security.sqla.models import User

    if g.get("user") is None:
        g.user = flask_db.session.query(User).filter_by(username=os.environ["SUPERSET_ADMIN_USERNAME"]).one()

    db_password = os.environ["DB_PASSWORD"]
    imported = []
    for path in sorted(glob.glob(os.path.join(EXPORTS_DIR, "*.zip"))):
        try:
            imported.append(_import_one(path, db_password))
        except Exception:
            logger.exception("Failed to import chart export: %s", os.path.basename(path))

    existing_ids = {s.id for s in dashboard.slices}
    all_charts = list(dashboard.slices) + [c for c in imported if c.id not in existing_ids]

    dashboard.slices = all_charts
    dashboard.position_json = build_position_json(all_charts)
    flask_db.session.commit()
    logger.info("Dashboard now has %d charts (%d from imports).", len(all_charts), len(imported))


if __name__ == "__main__":
    from superset.app import create_app

    app = create_app()
    with app.app_context(), app.test_request_context():
        from bootstrap import DASHBOARD_SLUG
        from superset import db as flask_db
        from superset.models.dashboard import Dashboard

        dashboard = flask_db.session.query(Dashboard).filter_by(slug=DASHBOARD_SLUG).one_or_none()
        if dashboard is None:
            logger.warning("Dashboard %s not found; run bootstrap.py first.", DASHBOARD_SLUG)
        else:
            import_and_attach(dashboard)
