# ADR 001: Paste an agenda parser

## Context
Users receive agendas as free text (emails, chat messages). We want to turn
pasted text into a structured agenda that the user checks and saves.

Claude on Bedrock was not available in my account: Opus 5.5 returned 403
("not available"), Sonnet 5.5 and Haiku 5.5 returned 404 ("does not exist"),
while Amazon Nova worked. The instructor allowed any model that works.

The project had no agenda feature, so I added it: three JSON columns on
`meetings` (`agenda`, `agenda_ai_suggestion`, `agenda_ai_meta`) via alembic
migration 0003, and the endpoint `PUT /meetings/{id}/agenda`.

## Decision
- A separate Lambda (function URL, outside the VPC, no database access) calls
  Amazon Nova Pro (`us.amazon.nova-pro-v1:0`) through the Bedrock Converse API
  with a `record_agenda` tool. The model ID is configuration (`PARSER_MODEL`).
- Output is validated with Pydantic, with one retry that shows the model its error.
- The function verifies the Cognito token (401), rejects text over 10,000
  characters (413) and logs one JSON line per parse with model, prompt version,
  tokens, latency and cost.
- The model never writes. The browser shows a pre-filled form with "suggested"
  badges, and Save goes through the existing API, which stores the agenda, the
  raw AI suggestion, the model and the prompt version.
- In `backend/Dockerfile` the base image is taken from the AWS mirror
  (`public.ecr.aws/docker/library/python`), because Docker Hub was too slow to
  download from my network. It is the same image (same digest).

## Consequences
- Switching models means changing `PARSER_MODEL`. We are not tied to one vendor,
  but we lose Claude-specific features.
- Nova Pro makes mistakes: wrong relative dates and UTC offsets, changed
  spelling, invented action items. Nova Micro is about 27 times cheaper but
  much worse (garbled text, invented values). The review form is necessary.
- Both models followed a prompt injection in the test input. Protection comes
  from the architecture (the model cannot write, a human reviews and saves),
  not from the prompt.
- The parser costs nothing while idle and about $0.003 per parse with Nova Pro.
