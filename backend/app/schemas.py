import uuid
from datetime import UTC, date, datetime
from typing import Annotated

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    EmailStr,
    StringConstraints,
    field_serializer,
    model_validator,
    Field
)

NonEmptyStr = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


def _require_tz(value: datetime) -> datetime:
    if value.tzinfo is None:
        raise ValueError("datetime must include a time-zone offset")
    return value.astimezone(UTC)


AwareDatetime = Annotated[datetime, AfterValidator(_require_tz)]


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    name: str


class ParticipantCreate(BaseModel):
    name: Annotated[NonEmptyStr, StringConstraints(max_length=100)]
    email: Annotated[EmailStr, StringConstraints(max_length=255)]


class ParticipantRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    email: str


class MeetingCreate(BaseModel):
    title: Annotated[NonEmptyStr, StringConstraints(max_length=200)]
    description: str = ""
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    place: Annotated[NonEmptyStr, StringConstraints(max_length=200)]
    participant_ids: list[uuid.UUID] = []

    @model_validator(mode="after")
    def check_times(self) -> MeetingCreate:
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        # de-duplicate while keeping order
        self.participant_ids = list(dict.fromkeys(self.participant_ids))
        return self

class AgendaItemData(BaseModel):
    topic: NonEmptyStr
    owner: str | None = None
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItemData(BaseModel):
    task: NonEmptyStr
    owner: str | None = None
    due: date | None = None


class AgendaData(BaseModel):
    items: list[AgendaItemData]
    action_items: list[ActionItemData] = []


class AgendaSave(BaseModel):
    agenda: AgendaData
    # The model's raw suggestion and where it came from, stored next to the saved agenda.
    ai_suggestion: dict | None = None
    model: str | None = None
    prompt_version: str | None = None
class MeetingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    description: str
    starts_at: datetime
    ends_at: datetime
    place: str
    participants: list[ParticipantRead]
    created_at: datetime
    agenda: dict | None = None
    agenda_ai_meta: dict | None = None

    @field_serializer("starts_at", "ends_at", "created_at")
    def to_utc(self, value: datetime) -> str:
        return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


class MeetingDraftRequest(BaseModel):
    text: Annotated[NonEmptyStr, StringConstraints(max_length=5000)]
    # The user's local wall-clock time, so "tomorrow at 3" resolves in their time zone.
    now: datetime


class MeetingDraft(BaseModel):
    """Form values guessed from what the user said; every field may be missing."""

    transcript: str
    title: str | None
    description: str | None
    date: date | None
    start_time: str | None
    end_time: str | None
    place: str | None
    participant_ids: list[uuid.UUID]
    # Names the user mentioned that match no known participant.
    unmatched_participants: list[str]
