from collections.abc import Iterator
from datetime import datetime
from types import SimpleNamespace

import httpx
import openai
import pytest
from httpx import AsyncClient

from app.assistant import MeetingAssistant, get_assistant
from app.config import settings
from app.main import app
from tests.test_api import make_participant


class FakeResponses:
    """Stands in for client.responses: records the request, answers with a canned extraction."""

    def __init__(self) -> None:
        self.extraction: dict | None = None
        self.error: Exception | None = None
        self.calls: list[dict] = []

    async def parse(self, *, text_format, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        parsed = text_format(**self.extraction) if self.extraction else None
        return SimpleNamespace(output_parsed=parsed)


class FakeTranscriptions:
    def __init__(self) -> None:
        self.text = ""
        self.files: list[tuple] = []

    async def create(self, *, file, model):
        self.files.append(file)
        return SimpleNamespace(text=self.text)


@pytest.fixture
def fake() -> Iterator[SimpleNamespace]:
    client = SimpleNamespace(
        responses=FakeResponses(),
        audio=SimpleNamespace(transcriptions=FakeTranscriptions()),
    )
    app.dependency_overrides[get_assistant] = lambda: MeetingAssistant(client)
    yield client
    app.dependency_overrides.pop(get_assistant, None)


def extraction(**overrides) -> dict:
    values = {
        "title": "Sprint planning",
        "description": None,
        "date": "2026-10-13",
        "start_time": "15:00",
        "end_time": "16:00",
        "place": "Room 204",
        "participant_ids": [],
        "unmatched_participants": [],
    }
    values.update(overrides)
    return values


NOW = "2026-10-12T09:30:00"


async def test_draft_from_text(client: AsyncClient, fake) -> None:
    olena = await make_participant(client, "Olena Koval", "olena@example.com")
    fake.responses.extraction = extraction(
        participant_ids=[olena["id"], "not-a-uuid", "00000000-0000-0000-0000-000000000000"],
        unmatched_participants=["Taras", " "],
    )

    text = "Sprint planning tomorrow 3-4pm in room 204 with Olena and Taras"
    response = await client.post("/api/meeting-drafts/text", json={"text": text, "now": NOW})

    assert response.status_code == 200, response.text
    assert response.json() == {
        "transcript": text,
        "title": "Sprint planning",
        "description": None,
        "date": "2026-10-13",
        "start_time": "15:00",
        "end_time": "16:00",
        "place": "Room 204",
        "participant_ids": [olena["id"]],
        "unmatched_participants": ["Taras"],
    }
    # The model sees the local time and the known participants.
    instructions = fake.responses.calls[0]["instructions"]
    assert "Monday, 2026-10-12 09:30" in instructions
    assert olena["id"] in instructions


async def test_draft_drops_malformed_values(client: AsyncClient, fake) -> None:
    fake.responses.extraction = extraction(
        title="  ", date="next week", start_time="3pm", end_time="25:00", place=""
    )

    response = await client.post("/api/meeting-drafts/text", json={"text": "a meeting", "now": NOW})

    body = response.json()
    assert (body["title"], body["date"], body["start_time"], body["end_time"], body["place"]) == (
        None,
        None,
        None,
        None,
        None,
    )


async def test_draft_drops_end_before_start(client: AsyncClient, fake) -> None:
    fake.responses.extraction = extraction(start_time="16:00", end_time="15:00")

    response = await client.post("/api/meeting-drafts/text", json={"text": "x", "now": NOW})

    assert response.json()["start_time"] == "16:00"
    assert response.json()["end_time"] is None


async def test_draft_requires_text(client: AsyncClient, fake) -> None:
    response = await client.post("/api/meeting-drafts/text", json={"text": "  ", "now": NOW})
    assert response.status_code == 422


async def test_draft_not_understood(client: AsyncClient, fake) -> None:
    response = await client.post("/api/meeting-drafts/text", json={"text": "hmm", "now": NOW})
    assert response.status_code == 422


async def test_draft_openai_failure(client: AsyncClient, fake) -> None:
    request = httpx.Request("POST", "https://api.openai.com/v1/responses")
    fake.responses.error = openai.APIConnectionError(request=request)

    response = await client.post("/api/meeting-drafts/text", json={"text": "x", "now": NOW})

    assert response.status_code == 502
    assert response.json()["detail"] == "Could not reach the assistant"


async def test_draft_from_audio(client: AsyncClient, fake) -> None:
    fake.audio.transcriptions.text = "Standup tomorrow at nine"
    fake.responses.extraction = extraction(title="Standup", start_time="09:00", end_time=None)

    response = await client.post(
        "/api/meeting-drafts/audio",
        files={"audio": ("blob", b"fake-audio", "audio/webm;codecs=opus")},
        data={"now": NOW},
    )

    assert response.status_code == 200, response.text
    assert response.json()["transcript"] == "Standup tomorrow at nine"
    assert response.json()["title"] == "Standup"
    assert fake.audio.transcriptions.files == [("recording.webm", b"fake-audio", "audio/webm")]
    assert fake.responses.calls[0]["input"] == "Standup tomorrow at nine"


async def test_draft_from_audio_rejects_other_files(client: AsyncClient, fake) -> None:
    response = await client.post(
        "/api/meeting-drafts/audio",
        files={"audio": ("notes.txt", b"hello", "text/plain")},
        data={"now": NOW},
    )
    assert response.status_code == 415


async def test_draft_from_silent_audio(client: AsyncClient, fake) -> None:
    response = await client.post(
        "/api/meeting-drafts/audio",
        files={"audio": ("blob", b"fake-audio", "audio/webm")},
        data={"now": NOW},
    )
    assert response.status_code == 422
    assert fake.responses.calls == []


async def test_assistant_not_configured(client: AsyncClient, monkeypatch) -> None:
    monkeypatch.setattr(settings, "openai_api_key", "")
    response = await client.post("/api/meeting-drafts/text", json={"text": "x", "now": NOW})
    assert response.status_code == 503


async def test_draft_requires_sign_in(client: AsyncClient, fake) -> None:
    response = await client.post(
        "/api/meeting-drafts/text",
        json={"text": "x", "now": datetime(2026, 10, 12).isoformat()},
        headers={"Authorization": ""},
    )
    assert response.status_code == 401
