"""Shared task callbacks for pipeline observability."""

from __future__ import annotations

import logging

logger = logging.getLogger("airflow.task.medallion_pipeline")


def log_failure(context: dict) -> None:
    task_instance = context["task_instance"]
    logger.error(
        "Task failed: dag=%s task=%s run_id=%s try=%s",
        task_instance.dag_id,
        task_instance.task_id,
        context["run_id"],
        task_instance.try_number,
    )


def log_success(context: dict) -> None:
    task_instance = context["task_instance"]
    logger.info(
        "Task succeeded: dag=%s task=%s run_id=%s",
        task_instance.dag_id,
        task_instance.task_id,
        context["run_id"],
    )
