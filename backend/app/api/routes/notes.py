from uuid import UUID

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.access import ensure_may_set_visibility, ensure_visible, visible_to
from app.api.deps import CurrentUser, SessionDep
from app.db.models import Note, User
from app.schemas.note import NoteCreate, NoteOut, NoteUpdate

router = APIRouter(prefix="/notes", tags=["notes"])


async def _get_owned_note(note_id: UUID, user: User, session: AsyncSession) -> Note:
    note = await session.get(Note, note_id)
    if note is None or note.family_id != user.family_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Заметка не найдена.")
    ensure_visible(user, note)
    return note


@router.get("", response_model=list[NoteOut])
async def list_notes(user: CurrentUser, session: SessionDep) -> list[NoteOut]:
    # Недавно изменённые сверху: заметка, которую правили последней,
    # обычно и есть та, к которой возвращаются.
    notes = await session.scalars(
        select(Note)
        .where(Note.family_id == user.family_id, visible_to(user, Note))
        .order_by(Note.updated_at.desc())
    )
    return [NoteOut.from_model(note) for note in notes]


@router.post("", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
async def create_note(payload: NoteCreate, user: CurrentUser, session: SessionDep) -> NoteOut:
    ensure_may_set_visibility(user, payload.visibility)

    note = Note(
        family_id=user.family_id,
        title=payload.title.strip(),
        body=payload.body,
        visibility=payload.visibility,
        author_id=user.id,
    )
    session.add(note)
    await session.commit()
    await session.refresh(note)

    return NoteOut.from_model(note)


@router.put("/{note_id}", response_model=NoteOut)
async def update_note(
    note_id: UUID,
    payload: NoteUpdate,
    user: CurrentUser,
    session: SessionDep,
) -> NoteOut:
    note = await _get_owned_note(note_id, user, session)
    ensure_may_set_visibility(user, payload.visibility)

    # Автора не переписываем: это тот, кто завёл заметку,
    # а править её может любой, кто её видит.
    note.title = payload.title.strip()
    note.body = payload.body
    note.visibility = payload.visibility

    await session.commit()
    await session.refresh(note)

    return NoteOut.from_model(note)


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note(note_id: UUID, user: CurrentUser, session: SessionDep) -> Response:
    note = await _get_owned_note(note_id, user, session)
    await session.delete(note)
    await session.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)
