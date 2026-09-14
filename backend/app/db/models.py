import uuid
from datetime import datetime
from enum import Enum, StrEnum

from sqlalchemy import DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy import Enum as SAEnum
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

from app.core.datetime_utils import utc_now


class Base(DeclarativeBase):
    pass


# --- Перечисления -------------------------------------------------------------
# Значения обязаны совпадать с raw value Swift-енумов на клиенте.


class FamilyRole(StrEnum):
    parent = "parent"
    child = "child"


class TaskPriority(StrEnum):
    low = "low"
    medium = "medium"
    high = "high"


class TaskStatus(StrEnum):
    todo = "todo"
    in_progress = "in_progress"
    done = "done"


class Visibility(StrEnum):
    """Кто видит запись. Общий механизм для задач и заметок.

    Enum, а не булев is_private: следом почти наверняка понадобится
    «личное, вижу только я», а миграция bool → enum дороже, чем сразу enum.
    """

    family = "family"
    parents = "parents"


def _enum_column(enum_cls: type[Enum], **kwargs):
    """Храним перечисления строками: их проще читать в базе и мигрировать."""
    return mapped_column(
        SAEnum(
            enum_cls,
            native_enum=False,
            values_callable=lambda members: [member.value for member in members],
            length=20,
        ),
        **kwargs,
    )


# --- Таблицы ------------------------------------------------------------------


class Family(Base):
    __tablename__ = "families"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(120))
    invite_code: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    members: Mapped[list["User"]] = relationship(back_populates="family")


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    family_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("families.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(80))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[FamilyRole] = _enum_column(FamilyRole, default=FamilyRole.parent)
    color_hex: Mapped[str | None] = mapped_column(String(7), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    family: Mapped[Family] = relationship(back_populates="members")


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    family_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("families.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    due_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    priority: Mapped[TaskPriority] = _enum_column(TaskPriority, default=TaskPriority.medium)
    status: Mapped[TaskStatus] = _enum_column(TaskStatus, default=TaskStatus.todo)
    # server_default обязателен: колонка добавляется в таблицу, где уже есть строки.
    visibility: Mapped[Visibility] = _enum_column(
        Visibility, default=Visibility.family, server_default=Visibility.family.value
    )

    assignee_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)

    assignee: Mapped[User | None] = relationship(foreign_keys=[assignee_id], lazy="selectin")


class Note(Base):
    """Заметка семьи: без сроков, статусов и исполнителей.

    Редактировать может любой, кто её видит, — это общий блокнот семьи,
    а не личные записи. Разграничение даёт `visibility`.
    """

    __tablename__ = "notes"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    family_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("families.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str | None] = mapped_column(Text, nullable=True)
    visibility: Mapped[Visibility] = _enum_column(
        Visibility, default=Visibility.family, server_default=Visibility.family.value
    )

    author_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)

    author: Mapped[User | None] = relationship(foreign_keys=[author_id], lazy="selectin")


class RefreshToken(Base):
    """Отдельная таблица нужна, чтобы refresh можно было отозвать при logout."""

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
