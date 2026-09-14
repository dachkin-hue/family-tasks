from fastapi import HTTPException, status
from sqlalchemy import ColumnElement, true

from app.db.models import FamilyRole, Note, Task, User, Visibility

# Правила доступа живут на сервере, а не в клиенте.
# Фильтрация в приложении спрятала бы записи с экрана, но они всё равно
# приехали бы по сети и осели в локальном кэше устройства.

Restricted = Task | Note


def visible_to(user: User, model: type[Restricted]) -> ColumnElement[bool]:
    """Условие для выборки: родитель видит всё, ребёнок — только общее."""
    if user.role is FamilyRole.parent:
        return true()
    return model.visibility == Visibility.family


def can_see(user: User, record: Restricted) -> bool:
    return user.role is FamilyRole.parent or record.visibility == Visibility.family


def ensure_visible(user: User, record: Restricted) -> None:
    """Скрытая запись — 404, а не 403.

    403 подтвердил бы, что запись с таким идентификатором существует.
    Для ребёнка её просто нет.
    """
    if not can_see(user, record):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Запись не найдена.")


def ensure_may_set_visibility(user: User, visibility: Visibility) -> None:
    if visibility is not Visibility.family and user.role is not FamilyRole.parent:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Скрывать записи от детей могут только родители.",
        )
