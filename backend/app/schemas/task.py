from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.db.models import Task, TaskPriority, TaskStatus, Visibility
from app.schemas.common import AwareDatetime


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=4000)
    due_date: datetime | None = None
    priority: TaskPriority = TaskPriority.medium
    assignee_id: UUID | None = None
    # Значение по умолчанию делает поле необязательным: клиент,
    # который о нём не знает, продолжает работать как раньше.
    visibility: Visibility = Visibility.family


class TaskUpdate(TaskCreate):
    """PUT — полная замена, поэтому статус приходит вместе с остальными полями."""

    status: TaskStatus = TaskStatus.todo


class TaskOut(BaseModel):
    id: UUID
    title: str
    notes: str | None
    due_date: AwareDatetime | None
    priority: TaskPriority
    status: TaskStatus
    visibility: Visibility
    assignee_id: UUID | None
    assignee_name: str | None
    created_by_id: UUID | None
    created_at: AwareDatetime
    updated_at: AwareDatetime

    @classmethod
    def from_model(cls, task: Task) -> "TaskOut":
        # assignee_name денормализован специально: клиент рисует список
        # без дополнительного запроса за участниками.
        return cls(
            id=task.id,
            title=task.title,
            notes=task.notes,
            due_date=task.due_date,
            priority=task.priority,
            status=task.status,
            visibility=task.visibility,
            assignee_id=task.assignee_id,
            assignee_name=task.assignee.name if task.assignee else None,
            created_by_id=task.created_by_id,
            created_at=task.created_at,
            updated_at=task.updated_at,
        )
