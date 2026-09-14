from uuid import UUID

from pydantic import BaseModel, Field

from app.db.models import Note, Visibility
from app.schemas.common import AwareDatetime


class NoteCreate(BaseModel):
    # Заголовок обязателен: по нему рисуется строка списка.
    # Текст необязателен — короткая заметка часто и есть один заголовок.
    title: str = Field(min_length=1, max_length=200)
    body: str | None = Field(default=None, max_length=10000)
    visibility: Visibility = Visibility.family


class NoteUpdate(NoteCreate):
    """PUT — полная замена, как и у задач."""


class NoteOut(BaseModel):
    id: UUID
    title: str
    body: str | None
    visibility: Visibility
    author_id: UUID | None
    author_name: str | None
    created_at: AwareDatetime
    updated_at: AwareDatetime

    @classmethod
    def from_model(cls, note: Note) -> "NoteOut":
        return cls(
            id=note.id,
            title=note.title,
            body=note.body,
            visibility=note.visibility,
            author_id=note.author_id,
            author_name=note.author.name if note.author else None,
            created_at=note.created_at,
            updated_at=note.updated_at,
        )
