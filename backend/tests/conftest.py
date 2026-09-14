import os
import pathlib
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager

import pytest

TEST_DB_PATH = pathlib.Path(__file__).parent / "test.db"

# Переменные окружения выставляем ДО импорта приложения:
# Settings кэшируется через lru_cache при первом обращении.
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{TEST_DB_PATH.as_posix()}"
os.environ["SECRET_KEY"] = "test-secret"

import httpx  # noqa: E402

from app.core import rate_limit  # noqa: E402
from app.core.config import settings  # noqa: E402
from app.db.models import Base  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture
async def prepared_app():
    """Чистая база и обнулённые счётчики на каждый тест.

    Лимитер живёт в памяти процесса, поэтому без сброса неудачные входы
    протекали бы из теста в тест.
    """
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
        await connection.run_sync(Base.metadata.create_all)
    await rate_limit.auth_limiter.reset_all()

    yield app

    await engine.dispose()


@pytest.fixture
async def client(prepared_app) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=prepared_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test/v1") as http_client:
        yield http_client


@pytest.fixture
def client_from_ip(prepared_app) -> Callable[[str], AsyncIterator[httpx.AsyncClient]]:
    """Клиент с подменённым адресом — для проверки лимита по IP."""

    @asynccontextmanager
    async def factory(ip: str) -> AsyncIterator[httpx.AsyncClient]:
        transport = httpx.ASGITransport(app=prepared_app, client=(ip, 51234))
        async with httpx.AsyncClient(transport=transport, base_url="http://test/v1") as http_client:
            yield http_client

    return factory


@pytest.fixture(autouse=True)
def relaxed_register_limit(monkeypatch) -> None:
    """Регистрация ограничена 5 в час на IP, а тесты создают аккаунты пачками.

    Поднимаем планку по умолчанию; тесты про сам лимит задают её явно
    через фикстуру auth_limits.
    """
    monkeypatch.setattr(settings, "register_rate_limit_ip_attempts", 1000)


@pytest.fixture
async def family(client) -> dict[str, dict]:
    """Семья из родителя и ребёнка плюс готовые заголовки авторизации.

    Ребёнок заводится по коду приглашения — это единственный способ
    получить роль child.
    """
    parent = (
        await client.post(
            "/auth/register",
            json={"name": "Александр", "email": "dad@example.com", "password": "secret"},
        )
    ).json()

    parent_headers = {"Authorization": f"Bearer {parent['access_token']}"}
    invite_code = (await client.get("/family", headers=parent_headers)).json()["invite_code"]

    child = (
        await client.post(
            "/auth/register",
            json={
                "name": "Соня",
                "email": "sonya@example.com",
                "password": "secret",
                "invite_code": invite_code,
            },
        )
    ).json()

    return {
        "parent": parent["user"],
        "child": child["user"],
        "parent_headers": parent_headers,
        "child_headers": {"Authorization": f"Bearer {child['access_token']}"},
    }


@pytest.fixture
def auth_limits(monkeypatch) -> Callable[..., None]:
    """Настройка лимитов под конкретный тест.

    Маршрут читает settings на каждом запросе, поэтому подмена работает
    без перезапуска приложения.
    """

    def apply(
        *,
        account_attempts: int = 5,
        account_window: int = 900,
        ip_attempts: int = 1000,
        ip_window: int = 300,
        register_attempts: int = 1000,
        register_window: int = 3600,
    ) -> None:
        monkeypatch.setattr(settings, "login_rate_limit_account_attempts", account_attempts)
        monkeypatch.setattr(settings, "login_rate_limit_account_window_seconds", account_window)
        monkeypatch.setattr(settings, "login_rate_limit_ip_attempts", ip_attempts)
        monkeypatch.setattr(settings, "login_rate_limit_ip_window_seconds", ip_window)
        monkeypatch.setattr(settings, "register_rate_limit_ip_attempts", register_attempts)
        monkeypatch.setattr(settings, "register_rate_limit_ip_window_seconds", register_window)

    return apply
