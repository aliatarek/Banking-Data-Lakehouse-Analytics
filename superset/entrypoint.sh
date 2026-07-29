#!/bin/bash
set -e

python /app/bootstrap.py wait-for-db

superset db upgrade

superset fab create-admin \
  --username "${SUPERSET_ADMIN_USERNAME}" \
  --firstname Admin --lastname User \
  --email "${SUPERSET_ADMIN_EMAIL}" \
  --password "${SUPERSET_ADMIN_PASSWORD}" || true

superset init

python /app/bootstrap.py bootstrap

python /app/sync_reporting_tables.py &

exec gunicorn \
  --bind "0.0.0.0:8088" \
  --workers 4 \
  --worker-class gthread \
  --threads 4 \
  --timeout 120 \
  --access-logfile - \
  --error-logfile - \
  "superset.app:create_app()"
