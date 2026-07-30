FROM apache/superset:4.1.2

USER root
RUN pip install --no-cache-dir psycopg2-binary
COPY superset_config.py /app/pythonpath/superset_config.py
COPY bootstrap.py /app/bootstrap.py
COPY import_dashboard_exports.py /app/import_dashboard_exports.py
COPY watch_dashboard_exports.py /app/watch_dashboard_exports.py
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh && chown -R superset:superset /app/bootstrap.py /app/import_dashboard_exports.py /app/watch_dashboard_exports.py /app/entrypoint.sh /app/pythonpath/superset_config.py

USER superset
ENTRYPOINT ["/app/entrypoint.sh"]
