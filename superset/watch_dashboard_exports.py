"""Background poller: watches EXPORTS_DIR for new or changed teammate
dashboard exports and re-runs the import automatically, without a container
restart or manual command.

Runs as a long-lived side process alongside gunicorn (started from
entrypoint.sh). Polls every POLL_SECONDS; the (cheap) per-cycle cost is just
an os.stat() over the export files. The (comparatively expensive) import only
runs when the directory's contents actually changed since the last check.
"""

from __future__ import annotations

import glob
import logging
import os
import time

logger = logging.getLogger("superset_bootstrap")

POLL_SECONDS = 60


def _manifest() -> dict[str, tuple[float, int]]:
    from import_dashboard_exports import EXPORTS_DIR

    manifest = {}
    for path in glob.glob(os.path.join(EXPORTS_DIR, "*.zip")):
        stat = os.stat(path)
        manifest[path] = (stat.st_mtime, stat.st_size)
    return manifest


def watch() -> None:
    from superset.app import create_app

    app = create_app()
    last_manifest = _manifest()
    logger.info("Dashboard-export watcher started (poll every %ss, %d file(s) tracked).", POLL_SECONDS, len(last_manifest))

    while True:
        time.sleep(POLL_SECONDS)
        try:
            current = _manifest()
            if current == last_manifest:
                continue

            logger.info("Detected change in superset_dashboard/, re-importing.")
            with app.app_context(), app.test_request_context():
                from import_dashboard_exports import import_all

                import_all()
            last_manifest = current
        except Exception:
            logger.exception("Dashboard-export watcher cycle failed; will retry next cycle.")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    watch()
