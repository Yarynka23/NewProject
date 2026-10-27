import json, logging, time
from datetime import date
from app.config import settings
from app.ai.agenda import parse_agenda, AgendaParseError, PROMPT_VERSION
from app.ai.auth import verify_cognito_token, AuthError
from app.ai.pricing import cost_usd

log = logging.getLogger()
log.setLevel(logging.INFO)   # без цього INFO-рядки не потраплять у CloudWatch
MAX_CHARS = 10_000

def _resp(code, obj):
    return {"statusCode": code, "headers": {"content-type": "application/json"},
            "body": json.dumps(obj)}

def handler(event, context):
    try:
        user = verify_cognito_token(event["headers"].get("authorization", ""))
    except AuthError:
        return _resp(401, {"error": "unauthorized"})
    try:
        body = json.loads(event.get("body") or "{}")
        text, today, tz = body["text"], date.fromisoformat(body["today"]), body["tz"]
    except (KeyError, ValueError, TypeError):
        return _resp(400, {"error": "bad request"})
    if len(text) > MAX_CHARS:
        return _resp(413, {"error": "text too long (max 10000 characters)"})

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        return _resp(422, {"error": str(e)})

    log.info(json.dumps({"event": "agenda_parsed", "user": user.sub,
        "model": settings.PARSER_MODEL, "prompt_version": PROMPT_VERSION, **usage,
        "latency_ms": int((time.monotonic() - started) * 1000),
        "cost_usd": cost_usd(settings.PARSER_MODEL, usage)}))
    return _resp(200, {"agenda": agenda.model_dump(mode="json"),
                       "model": settings.PARSER_MODEL, "prompt_version": PROMPT_VERSION})
