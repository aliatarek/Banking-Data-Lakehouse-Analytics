-- Runs once when the platform-db container's data volume is first created.
-- Airflow's own metadata lives in the default POSTGRES_DB ("airflow"); Superset gets a sibling database.
CREATE DATABASE superset;
