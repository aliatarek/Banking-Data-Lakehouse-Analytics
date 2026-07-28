# slim base: the "full" apache/airflow image bundles providers this project never
# uses (Azure, Snowflake, BigQuery, Spanner, pandas-gbq, ...) — ~2.3GB vs ~800MB.
# Providers actually needed (postgres/celery/fab) are installed explicitly below.
FROM apache/airflow:slim-3.3.0-python3.12

USER airflow

COPY airflow/requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# dbt project (models, macros, profiles.yml) baked into the image so Cosmos
# (execution_mode=LOCAL) can invoke the dbt binary in-process against it.
COPY --chown=airflow:root dbt /opt/airflow/dbt
