"""Тесты проверяют не «работает ли Python», а совпадение с контрактом iOS-клиента.

Каждая проверка ниже соответствует конкретной строчке Swift-кода:
имена ключей, значения enum, наличие часового пояса в датах, коды ошибок.
"""

import re

import pytest

ISO_WITH_TZ = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:\d{2}|Z)$")


async def register(client, name="Александр", email="dad@example.com", password="secret"):
    response = await client.post(
        "/auth/register",
        json={"name": name, "email": email, "password": password},
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(payload: dict) -> dict:
    return {"Authorization": f"Bearer {payload['access_token']}"}


@pytest.mark.asyncio
async def test_register_returns_contract_shape(client):
    body = await register(client)

    assert set(body) == {"access_token", "refresh_token", "expires_in", "user"}
    assert isinstance(body["expires_in"], int) and body["expires_in"] > 0

    # Ключи в snake_case — iOS декодирует через convertFromSnakeCase.
    assert set(body["user"]) == {"id", "name", "email", "role", "color_hex"}
    assert body["user"]["role"] == "parent"


@pytest.mark.asyncio
async def test_login_and_me(client):
    await register(client)

    response = await client.post(
        "/auth/login", json={"email": "dad@example.com", "password": "secret"}
    )
    assert response.status_code == 200
    tokens = response.json()

    me = await client.get("/me", headers=auth_header(tokens))
    assert me.status_code == 200
    assert me.json()["email"] == "dad@example.com"


@pytest.mark.asyncio
async def test_login_with_wrong_password_returns_401_with_detail(client):
    await register(client)

    response = await client.post(
        "/auth/login", json={"email": "dad@example.com", "password": "wrong"}
    )
    assert response.status_code == 401
    # APIError.swift читает именно поле detail.
    assert isinstance(response.json()["detail"], str)


@pytest.mark.asyncio
async def test_missing_token_returns_401(client):
    response = await client.get("/tasks")
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_task_crud_matches_swift_model(client):
    auth = await register(client)
    headers = auth_header(auth)
    user_id = auth["user"]["id"]

    created = await client.post(
        "/tasks",
        headers=headers,
        json={
            "title": "Забрать Соню с тренировки",
            "notes": "Секция заканчивается в 18:30",
            "due_date": "2026-09-13T18:00:00+03:00",
            "priority": "high",
            "assignee_id": user_id,
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()

    assert set(task) == {
        "id", "title", "notes", "due_date", "priority", "status", "visibility",
        "assignee_id", "assignee_name", "created_by_id", "created_at", "updated_at",
    }
    # Клиент поле ещё не знает, но Codable игнорирует лишние ключи,
    # а на запись оно необязательное — обратная совместимость сохранена.
    assert task["visibility"] == "family"
    assert task["status"] == "todo"
    assert task["priority"] == "high"
    assert task["assignee_name"] == "Александр"

    # Даты обязаны нести часовой пояс, иначе ISO8601DateFormatter на iOS вернёт nil.
    for field in ("due_date", "created_at", "updated_at"):
        assert ISO_WITH_TZ.match(task[field]), f"{field} = {task[field]}"

    listed = await client.get("/tasks", headers=headers)
    assert listed.status_code == 200
    assert len(listed.json()) == 1

    updated = await client.put(
        f"/tasks/{task['id']}",
        headers=headers,
        json={
            "title": "Забрать Соню с тренировки",
            "notes": None,
            "due_date": None,
            "priority": "medium",
            "status": "in_progress",
            "assignee_id": None,
        },
    )
    assert updated.status_code == 200
    # Именно "in_progress": в Swift raw value задан явно.
    assert updated.json()["status"] == "in_progress"
    assert updated.json()["due_date"] is None
    assert updated.json()["assignee_name"] is None

    deleted = await client.delete(f"/tasks/{task['id']}", headers=headers)
    assert deleted.status_code == 204

    assert (await client.get("/tasks", headers=headers)).json() == []


@pytest.mark.asyncio
async def test_task_of_another_family_is_not_visible(client):
    first = await register(client)
    second = await register(client, name="Чужой", email="other@example.com")

    created = await client.post(
        "/tasks", headers=auth_header(first), json={"title": "Приватная задача"}
    )
    task_id = created.json()["id"]

    listed = await client.get("/tasks", headers=auth_header(second))
    assert listed.json() == []

    # 404, а не 403 — чтобы не подтверждать существование чужой записи.
    assert (await client.get("/tasks", headers=auth_header(second))).status_code == 200
    assert (
        await client.delete(f"/tasks/{task_id}", headers=auth_header(second))
    ).status_code == 404


@pytest.mark.asyncio
async def test_refresh_rotates_token_and_revokes_old(client):
    auth = await register(client)

    refreshed = await client.post(
        "/auth/refresh", json={"refresh_token": auth["refresh_token"]}
    )
    assert refreshed.status_code == 200
    assert set(refreshed.json()) == {"access_token", "refresh_token", "expires_in"}
    assert refreshed.json()["refresh_token"] != auth["refresh_token"]

    # Повторное использование старого токена запрещено.
    reused = await client.post(
        "/auth/refresh", json={"refresh_token": auth["refresh_token"]}
    )
    assert reused.status_code == 401

    # Новый токен продолжает работать.
    me = await client.get("/me", headers=auth_header(refreshed.json()))
    assert me.status_code == 200


@pytest.mark.asyncio
async def test_logout_revokes_refresh_tokens(client):
    auth = await register(client)

    logout = await client.post("/auth/logout", headers=auth_header(auth))
    assert logout.status_code == 204

    after = await client.post("/auth/refresh", json={"refresh_token": auth["refresh_token"]})
    assert after.status_code == 401


@pytest.mark.asyncio
async def test_invite_code_joins_existing_family(client):
    parent = await register(client)

    family = await client.get("/family", headers=auth_header(parent))
    invite_code = family.json()["invite_code"]

    child = await client.post(
        "/auth/register",
        json={
            "name": "Соня",
            "email": "sonya@example.com",
            "password": "secret",
            "invite_code": invite_code,
        },
    )
    assert child.status_code == 200
    assert child.json()["user"]["role"] == "child"

    members = await client.get("/family/members", headers=auth_header(parent))
    assert [member["name"] for member in members.json()] == ["Александр", "Соня"]


@pytest.mark.asyncio
async def test_validation_error_shape(client):
    auth = await register(client)

    response = await client.post("/tasks", headers=auth_header(auth), json={"title": ""})
    assert response.status_code == 422
    # NetworkManager.serverMessage разбирает detail как список объектов с msg.
    detail = response.json()["detail"]
    assert isinstance(detail, list)
    assert "msg" in detail[0]


@pytest.mark.asyncio
async def test_duplicate_email_returns_409(client):
    await register(client)
    response = await client.post(
        "/auth/register",
        json={"name": "Дубль", "email": "dad@example.com", "password": "secret"},
    )
    assert response.status_code == 409
    assert isinstance(response.json()["detail"], str)
