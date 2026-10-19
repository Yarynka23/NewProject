from datetime import datetime
from typing import Annotated

import openai
from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status
from sqlalchemy import select

from app.assistant import AssistantDep, openai_error
from app.auth import CurrentUser
from app.db import SessionDep
from app.models import Participant
from app.schemas import MeetingDraft, MeetingDraftRequest

router = APIRouter(prefix="/meeting-drafts", tags=["meeting drafts"])

# A Lambda function URL accepts at most 6 MB per request; a two-minute voice note is far less.
MAX_AUDIO_BYTES = 4 * 1024 * 1024
AUDIO_EXTENSIONS = {
    "audio/webm": "webm",
    "audio/ogg": "ogg",
    "audio/mp4": "mp4",
    "audio/m4a": "m4a",
    "audio/x-m4a": "m4a",
    "audio/mpeg": "mp3",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
}


async def _participants(session: SessionDep) -> list[Participant]:
    return list(await session.scalars(select(Participant).order_by(Participant.name)))


@router.post("/text", response_model=MeetingDraft)
async def draft_from_text(
    payload: MeetingDraftRequest, session: SessionDep, assistant: AssistantDep, _: CurrentUser
) -> MeetingDraft:
    participants = await _participants(session)
    try:
        return await assistant.draft(payload.text, payload.now, participants)
    except openai.OpenAIError as error:
        raise openai_error(error) from error


@router.post("/audio", response_model=MeetingDraft)
async def draft_from_audio(
    audio: Annotated[UploadFile, File()],
    now: Annotated[datetime, Form()],
    session: SessionDep,
    assistant: AssistantDep,
    _: CurrentUser,
) -> MeetingDraft:
    # Browsers add codec details, e.g. "audio/webm;codecs=opus".
    content_type = (audio.content_type or "").split(";")[0].strip().lower()
    extension = AUDIO_EXTENSIONS.get(content_type)
    if extension is None:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, f"Unsupported audio format: {content_type}"
        )
    data = await audio.read(MAX_AUDIO_BYTES + 1)
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "The recording is too long")
    if not data:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "The recording is empty")

    participants = await _participants(session)
    try:
        text = await assistant.transcribe(data, f"recording.{extension}", content_type)
        if not text:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_CONTENT, "No speech was recognised, try again"
            )
        return await assistant.draft(text, now, participants)
    except openai.OpenAIError as error:
        raise openai_error(error) from error
