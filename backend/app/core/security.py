import hashlib
import secrets
import string
from datetime import UTC, datetime, timedelta
from uuid import UUID

import bcrypt
import jwt

from app.core.config import settings

_BCRYPT_MAX_BYTES = 72  # bcrypt молча обрезает всё, что длиннее


def hash_password(password: str) -> str:
    payload = password.encode("utf-8")[:_BCRYPT_MAX_BYTES]
    return bcrypt.hashpw(payload, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        payload = password.encode("utf-8")[:_BCRYPT_MAX_BYTES]
        return bcrypt.checkpw(payload, password_hash.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def create_access_token(user_id: UUID) -> tuple[str, int]:
    """Возвращает (токен, срок жизни в секундах) — второе уходит в поле expires_in."""
    expires_in = settings.access_token_expire_minutes * 60
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(seconds=expires_in),
        "type": "access",
    }
    token = jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)
    return token, expires_in


def decode_access_token(token: str) -> UUID | None:
    """None означает «токен невалиден или истёк» — вызывающий отдаёт 401."""
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
    except jwt.PyJWTError:
        return None

    if payload.get("type") != "access":
        return None

    try:
        return UUID(payload["sub"])
    except (KeyError, ValueError, TypeError):
        return None


def generate_refresh_token() -> str:
    """Refresh — не JWT, а непрозрачная случайная строка.

    Так его можно отозвать: в базе лежит только хеш, при logout запись помечается revoked.
    """
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def refresh_token_expiry() -> datetime:
    return datetime.now(UTC) + timedelta(days=settings.refresh_token_expire_days)


def generate_invite_code(length: int = 6) -> str:
    alphabet = string.ascii_uppercase + string.digits
    # Без похожих символов, чтобы код было легко продиктовать голосом.
    alphabet = alphabet.translate(str.maketrans("", "", "OI01"))
    return "".join(secrets.choice(alphabet) for _ in range(length))
