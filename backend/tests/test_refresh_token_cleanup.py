"""Таблица refresh_tokens не должна расти бесконечно."""

from datetime import timedelta

import pytest
from sqlalchemy import func, select

from app.core.datetime_utils import utc_now
from app.core.security import hash_refresh_token
from app.db.models import RefreshToken, User
from app.db.session import SessionFactory

PASSWORD = "secret"
EMAIL = "dad@example.com"


async def _count_tokens() -> int:
    async with SessionFactory() as session:
        return await session.scalar(select(func.count()).select_from(RefreshToken)) or 0


async def _add_stale_token(offset_days: int, *, revoked: bool = False) -> None:
    async with SessionFactory() as session:
        user = await session.scalar(select(User).where(User.email == EMAIL))
        assert user is not None
        session.add(
            RefreshToken(
                user_id=user.id,
                token_hash=hash_refresh_token(f"stale-{offset_days}-{revoked}"),
                expires_at=utc_now() + timedelta(days=offset_days),
                revoked_at=utc_now() if revoked else None,
            )
        )
        await session.commit()


@pytest.mark.asyncio
async def test_expired_tokens_are_removed_on_next_login(client):
    await client.post(
        "/auth/register", json={"name": "Александр", "email": EMAIL, "password": PASSWORD}
    )
    assert await _count_tokens() == 1

    await _add_stale_token(-10)
    await _add_stale_token(-1)
    assert await _count_tokens() == 3

    login = await client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert login.status_code == 200

    # Остались только живой токен от регистрации и свежий от входа.
    assert await _count_tokens() == 2


@pytest.mark.asyncio
async def test_revoked_but_valid_tokens_are_kept(client):
    """По ним позже можно будет ловить повторное использование украденного токена."""
    await client.post(
        "/auth/register", json={"name": "Александр", "email": EMAIL, "password": PASSWORD}
    )
    await _add_stale_token(10, revoked=True)
    assert await _count_tokens() == 2

    await client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})

    assert await _count_tokens() == 3
