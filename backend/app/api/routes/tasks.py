from uuid import UUID

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.access import ensure_may_set_visibility, ensure_visible, visible_to
from app.api.deps import CurrentUser, SessionDep
from app.core.datetime_utils import to_utc
from app.db.models import FamilyRole, Task, User, Visibility
from app.schemas.task import TaskCreate, TaskOut, TaskUpdate

router = APIRouter(prefix="/tasks", tags=["tasks"])


async def _get_owned_task(task_id: UUID, user: User, session: AsyncSession) -> Task:
    """Чужую задачу отдаём как 404, а не 403.

    403 подтвердил бы, что задача с таким id существует, — лишняя утечка.
    То же самое делает ensure_visible для задач, скрытых от детей.
    """
    task = await session.get(Task, task_id)
    if task is None or task.family_id != user.family_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Задача не найдена.")
    ensure_visible(user, task)
    return task


async def _resolve_assignee(assignee_id: UUID | None, user: User, session: AsyncSession) -> User | None:
    if assignee_id is None:
        return None
    assignee = await session.get(User, assignee_id)
    if assignee is None or assignee.family_id != user.family_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Исполнитель не найден в вашей семье.",
        )
    return assignee


def _ensure_assignee_can_see(visibility: Visibility, assignee: User | None) -> None:
    """Задача, скрытая от детей, не может висеть на ребёнке.

    Иначе она была бы назначена человеку, который её не видит,
    и он не понимал бы, почему с него что-то спрашивают.
    """
    if visibility is Visibility.parents and assignee is not None and assignee.role is FamilyRole.child:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Задачу, скрытую от детей, нельзя назначить ребёнку.",
        )


@router.get("", response_model=list[TaskOut])
async def list_tasks(user: CurrentUser, session: SessionDep) -> list[TaskOut]:
    tasks = await session.scalars(
        select(Task)
        .where(Task.family_id == user.family_id, visible_to(user, Task))
        .order_by(Task.created_at.desc())
    )
    return [TaskOut.from_model(task) for task in tasks]


@router.post("", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
async def create_task(payload: TaskCreate, user: CurrentUser, session: SessionDep) -> TaskOut:
    ensure_may_set_visibility(user, payload.visibility)
    assignee = await _resolve_assignee(payload.assignee_id, user, session)
    _ensure_assignee_can_see(payload.visibility, assignee)

    task = Task(
        family_id=user.family_id,
        title=payload.title.strip(),
        notes=payload.notes,
        due_date=to_utc(payload.due_date),
        priority=payload.priority,
        visibility=payload.visibility,
        assignee_id=payload.assignee_id,
        created_by_id=user.id,
    )
    session.add(task)
    await session.commit()
    await session.refresh(task)

    return TaskOut.from_model(task)


@router.put("/{task_id}", response_model=TaskOut)
async def update_task(
    task_id: UUID,
    payload: TaskUpdate,
    user: CurrentUser,
    session: SessionDep,
) -> TaskOut:
    task = await _get_owned_task(task_id, user, session)
    ensure_may_set_visibility(user, payload.visibility)
    assignee = await _resolve_assignee(payload.assignee_id, user, session)
    _ensure_assignee_can_see(payload.visibility, assignee)

    task.title = payload.title.strip()
    task.notes = payload.notes
    task.due_date = to_utc(payload.due_date)
    task.priority = payload.priority
    task.status = payload.status
    task.visibility = payload.visibility
    task.assignee_id = payload.assignee_id

    await session.commit()
    await session.refresh(task)

    return TaskOut.from_model(task)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(task_id: UUID, user: CurrentUser, session: SessionDep) -> Response:
    task = await _get_owned_task(task_id, user, session)
    await session.delete(task)
    await session.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)
