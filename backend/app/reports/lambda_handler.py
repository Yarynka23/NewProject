import json
import logging
import os
import boto3

from app.reports.weekly import build_weekly_report, previous_iso_week

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")


def detect_trigger(event: dict) -> str:
    """Визначає, звідки прийшов виклик: sqs, schedule чи прямий виклик."""
    records = event.get("Records")
    if records and records[0].get("eventSource") == "aws:sqs":
        try:
            body = json.loads(records[0].get("body", "{}"))
            if body.get("source") == "schedule":
                return "schedule"
        except Exception:
            pass
        return "sqs"

    if event.get("source") == "schedule":
        return "schedule"

    return "direct"


def extract_week(event: dict) -> str:
    """Дістає тиждень з події (SQS або direct). Якщо не вказано — бере попередній."""
    records = event.get("Records")
    if records and records[0].get("eventSource") == "aws:sqs":
        try:
            body = json.loads(records[0].get("body", "{}"))
            week = body.get("week")
            if week:
                return week
        except Exception:
            pass

    week = event.get("week")
    if week:
        return week

    return previous_iso_week()


def handler(event, context):
    trigger = detect_trigger(event)
    week = extract_week(event)

    # Цей рядок обов'язковий за умовою для перевірки в CloudWatch
    logger.info("report-builder triggered", extra={"trigger": trigger, "week": week})

    bucket = os.environ.get("REPORTS_BUCKET")
    if not bucket:
        raise RuntimeError("REPORTS_BUCKET environment variable is not set")

    csv_data = build_weekly_report(week)
    key = f"reports/{week}.csv"

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=csv_data,
        ContentType="text/csv",
    )

    return {
        "status": "ok",
        "week": week,
        "key": key,
        "trigger": trigger,
    }
