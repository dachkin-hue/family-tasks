from datetime import UTC, datetime


def utc_now() -> datetime:
    return datetime.now(UTC)


def to_utc(value: datetime | None) -> datetime | None:
    """Приводит входящую дату к UTC.

    Важно для SQLite: его тип DATETIME хранит строку без смещения, поэтому
    tz-aware значение записалось бы «как есть» и потеряло бы часовой пояс.
    Нормализуем на входе — тогда в базе всегда UTC, независимо от СУБД.
    """
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def as_aware(value: datetime) -> datetime:
    """Наивные значения, прочитанные из SQLite, считаем UTC."""
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value
