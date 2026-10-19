"""Meeting assistant: turns free text or speech into a meeting draft with OpenAI.

Nothing is saved here. The draft prefills the meeting form, and the user reviews it and
creates the meeting through the regular API.
"""

import json
import re
import uuid
from datetime import date, datetime
from typing import Annotated

import openai
from fastapi import Depends, HTTPException, status
from openai import AsyncOpenAI
from pydantic import BaseModel

from app.config import settings
from app.models import Participant
from app.schemas import MeetingDraft

INSTRUCTIONS = """\
You fill in a "new meeting" form from what the user wrote or said. The input may be in any \
language; keep the user's language for the title and description.

Fields:
- title: a short title (at most 200 characters).
- description: agenda or other details the user gave; null if there are none. Do not invent.
- date: the meeting date as YYYY-MM-DD. Resolve relative dates ("tomorrow", "next Friday") \
from the current local time given below.
- start_time, end_time: 24-hour HH:MM local times. If only a duration is given, compute the \
end. If only the start is given, leave end_time null.
- place: a room, address, or video link; null if not mentioned.
- participant_ids: ids from the known participants list for every person the user mentioned \
who clearly matches one entry (by name, first name, or email).
- unmatched_participants: names of mentioned people who match no known participant, or match \
several equally well.

Use null for anything the user did not say. Never guess a date, time, or place."""


class _Extraction(BaseModel):
    title: str | None
    description: str | None
    date: str | None
    start_time: str | None
    end_time: str | None
    place: str | None
    participant_ids: list[str]
    unmatched_participants: list[str]


_TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def _time(value: str | None) -> str | None:
    return value if value and _TIME.match(value) else None


def _date(value: str | None) -> date | None:
    try:
        return date.fromisoformat(value) if value else None
    except ValueError:
        return None


def _text(value: str | None, limit: int | None = None) -> str | None:
    value = (value or "").strip()
    return value[:limit] if value else None


class MeetingAssistant:
    def __init__(self, client: AsyncOpenAI) -> None:
        self.client = client

    async def transcribe(self, audio: bytes, filename: str, content_type: str) -> str:
        result = await self.client.audio.transcriptions.create(
            file=(filename, audio, content_type),
            model=settings.openai_transcription_model,
        )
        return result.text.strip()

    async def draft(
        self, text: str, now: datetime, participants: list[Participant]
    ) -> MeetingDraft:
        known = [{"id": str(p.id), "name": p.name, "email": p.email} for p in participants]
        context = (
            f"Current local time: {now:%A, %Y-%m-%d %H:%M}\n"
            f"Known participants: {json.dumps(known, ensure_ascii=False)}"
        )
        response = await self.client.responses.parse(
            model=settings.openai_model,
            instructions=f"{INSTRUCTIONS}\n\n{context}",
            input=text,
            text_format=_Extraction,
        )
        extraction = response.output_parsed
        if extraction is None:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_CONTENT, "Could not understand the meeting details"
            )

        # The model may only point at participants we gave it.
        known_ids = {p.id for p in participants}
        participant_ids: list[uuid.UUID] = []
        for raw in extraction.participant_ids:
            try:
                pid = uuid.UUID(raw)
            except ValueError:
                continue
            if pid in known_ids and pid not in participant_ids:
                participant_ids.append(pid)

        start, end = _time(extraction.start_time), _time(extraction.end_time)
        if start and end and end <= start:
            end = None

        return MeetingDraft(
            transcript=text,
            title=_text(extraction.title, 200),
            description=_text(extraction.description),
            date=_date(extraction.date),
            start_time=start,
            end_time=end,
            place=_text(extraction.place, 200),
            participant_ids=participant_ids,
            unmatched_participants=[
                name.strip() for name in extraction.unmatched_participants if name.strip()
            ],
        )


def get_assistant() -> MeetingAssistant:
    if not settings.openai_api_key:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "The meeting assistant is not configured (OPENAI_API_KEY is not set)",
        )
    return MeetingAssistant(AsyncOpenAI(api_key=settings.openai_api_key, timeout=60))


AssistantDep = Annotated[MeetingAssistant, Depends(get_assistant)]


def openai_error(error: openai.OpenAIError) -> HTTPException:
    """An OpenAI failure as an API error the frontend can show."""
    if isinstance(error, openai.RateLimitError):
        return HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "The assistant is busy, try again shortly"
        )
    if isinstance(error, openai.APIConnectionError):
        return HTTPException(status.HTTP_502_BAD_GATEWAY, "Could not reach the assistant")
    if isinstance(error, openai.BadRequestError):
        return HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "The assistant could not process this input"
        )
    return HTTPException(status.HTTP_502_BAD_GATEWAY, "The assistant failed, try again")
