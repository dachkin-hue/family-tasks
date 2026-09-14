"""Ограничение частоты для /auth/login и /auth/register — через HTTP, как это увидит клиент."""

import pytest

PASSWORD = "secret"


async def register(client, name="Александр", email="dad@example.com"):
    response = await client.post(
        "/auth/register", json={"name": name, "email": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()


async def wrong_login(client, email="dad@example.com"):
    return await client.post("/auth/login", json={"email": email, "password": "wrong"})


@pytest.mark.asyncio
async def test_account_is_locked_after_too_many_failures(client, auth_limits):
    auth_limits(account_attempts=3)
    await register(client)

    for attempt in range(3):
        assert (await wrong_login(client)).status_code == 401, f"попытка {attempt}"

    blocked = await wrong_login(client)
    assert blocked.status_code == 429
    # Клиент читает detail и показывает его пользователю.
    assert isinstance(blocked.json()["detail"], str)
    assert "Retry-After" in blocked.headers
    assert int(blocked.headers["Retry-After"]) > 0


@pytest.mark.asyncio
async def test_correct_password_is_rejected_while_locked(client, auth_limits):
    """Главное свойство: после блокировки не проходит даже верный пароль."""
    auth_limits(account_attempts=2)
    await register(client)

    await wrong_login(client)
    await wrong_login(client)

    response = await client.post(
        "/auth/login", json={"email": "dad@example.com", "password": PASSWORD}
    )
    assert response.status_code == 429


@pytest.mark.asyncio
async def test_successful_login_resets_counter(client, auth_limits):
    auth_limits(account_attempts=3)
    await register(client)

    await wrong_login(client)
    await wrong_login(client)

    ok = await client.post("/auth/login", json={"email": "dad@example.com", "password": PASSWORD})
    assert ok.status_code == 200

    # Счётчик обнулён — снова доступны все три попытки.
    for _ in range(3):
        assert (await wrong_login(client)).status_code == 401
    assert (await wrong_login(client)).status_code == 429


@pytest.mark.asyncio
async def test_unknown_email_is_limited_the_same_way(client, auth_limits):
    """Иначе 429 приходил бы только по существующим адресам и сам стал бы утечкой."""
    auth_limits(account_attempts=3)

    for _ in range(3):
        assert (await wrong_login(client, email="nobody@example.com")).status_code == 401

    assert (await wrong_login(client, email="nobody@example.com")).status_code == 429


@pytest.mark.asyncio
async def test_other_account_stays_available(client, auth_limits):
    auth_limits(account_attempts=2)
    await register(client)
    await register(client, name="Мария", email="mom@example.com")

    await wrong_login(client)
    await wrong_login(client)
    assert (await wrong_login(client)).status_code == 429

    # Блокировка одного аккаунта не мешает войти другому члену семьи.
    other = await client.post(
        "/auth/login", json={"email": "mom@example.com", "password": PASSWORD}
    )
    assert other.status_code == 200


@pytest.mark.asyncio
async def test_ip_limit_covers_password_spraying(client_from_ip, auth_limits):
    """Перебор по многим аккаунтам с одного адреса ловится лимитом по IP."""
    auth_limits(account_attempts=100, ip_attempts=3)

    async with client_from_ip("203.0.113.10") as attacker:
        for index in range(3):
            response = await wrong_login(attacker, email=f"victim{index}@example.com")
            assert response.status_code == 401

        blocked = await wrong_login(attacker, email="victim4@example.com")
        assert blocked.status_code == 429


@pytest.mark.asyncio
async def test_other_ip_is_not_affected(client_from_ip, auth_limits):
    auth_limits(account_attempts=100, ip_attempts=2)

    async with client_from_ip("203.0.113.10") as attacker:
        await register(attacker)
        await wrong_login(attacker)
        await wrong_login(attacker)
        assert (await wrong_login(attacker)).status_code == 429

    async with client_from_ip("198.51.100.20") as family_member:
        response = await family_member.post(
            "/auth/login", json={"email": "dad@example.com", "password": PASSWORD}
        )
        assert response.status_code == 200


@pytest.mark.asyncio
async def test_register_is_limited_per_ip(client, auth_limits):
    """У регистрации считаются ВСЕ попытки, включая успешные."""
    auth_limits(register_attempts=3)

    for index in range(3):
        response = await client.post(
            "/auth/register",
            json={"name": f"Гость {index}", "email": f"guest{index}@example.com", "password": PASSWORD},
        )
        assert response.status_code == 200, response.text

    blocked = await client.post(
        "/auth/register",
        json={"name": "Лишний", "email": "extra@example.com", "password": PASSWORD},
    )
    assert blocked.status_code == 429
    assert "регистрации" in blocked.json()["detail"]
    assert int(blocked.headers["Retry-After"]) > 0


@pytest.mark.asyncio
async def test_failed_registration_also_counts(client, auth_limits):
    """Иначе лимит обходится повторами заведомо неудачных запросов."""
    auth_limits(register_attempts=2)

    await client.post(
        "/auth/register", json={"name": "Раз", "email": "one@example.com", "password": PASSWORD}
    )
    # Дубликат почты — 409, но попытка всё равно израсходована.
    duplicate = await client.post(
        "/auth/register", json={"name": "Раз", "email": "one@example.com", "password": PASSWORD}
    )
    assert duplicate.status_code == 409

    blocked = await client.post(
        "/auth/register", json={"name": "Два", "email": "two@example.com", "password": PASSWORD}
    )
    assert blocked.status_code == 429
