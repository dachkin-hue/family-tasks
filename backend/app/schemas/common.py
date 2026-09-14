from datetime import datetime
from typing import Annotated

from pydantic import PlainSerializer

from app.core.datetime_utils import as_aware


def _serialize(value: datetime) -> str:
    return as_aware(value).isoformat()


# iOS-клиент разбирает даты через ISO8601DateFormatter с .withInternetDateTime,
# а он ТРЕБУЕТ указания часового пояса. Отдать наивное "2026-09-13T18:00:00"
# значит уронить декодирование на клиенте, поэтому смещение добавляем всегда.
AwareDatetime = Annotated[
    datetime,
    PlainSerializer(_serialize, return_type=str, when_used="json"),
]
