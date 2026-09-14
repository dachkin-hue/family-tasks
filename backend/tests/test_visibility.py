"""Задачи и заметки, скрытые от детей.

Проверяем именно серверные правила: фильтрация в клиенте не считается защитой,
потому что данные всё равно приехали бы на устройство ребёнка.
"""

import pytest


async def create_task(client, headers, title="Разговор про подарок", **extra):
    payload = {"title": title, **extra}
    return await client.post("/tasks", headers=headers, json=payload)


@pytest.mark.asyncio
async def test_visibility_defaults_to_family(client, family):
    created = await create_task(client, family["parent_headers"], title="Купить продукты")

    assert created.status_code == 201
    assert created.json()["visibility"] == "family"

    listed = await client.get("/tasks", headers=family["child_headers"])
    assert [t["title"] for t in listed.json()] == ["Купить продукты"]


@pytest.mark.asyncio
async def test_child_does_not_see_parents_only_task(client, family):
    await create_task(client, family["parent_headers"], visibility="parents")
    await create_task(client, family["parent_headers"], title="Вынести мусор")

    parent_list = await client.get("/tasks", headers=family["parent_headers"])
    assert len(parent_list.json()) == 2

    child_list = await client.get("/tasks", headers=family["child_headers"])
    assert [t["title"] for t in child_list.json()] == ["Вынести мусор"]


@pytest.mark.asyncio
async def test_child_gets_404_on_direct_access(client, family):
    """404, а не 403: 403 подтвердил бы, что такая задача существует."""
    hidden = await create_task(client, family["parent_headers"], visibility="parents")
    task_id = hidden.json()["id"]

    update = await client.put(
        f"/tasks/{task_id}",
        headers=family["child_headers"],
        json={"title": "Подмена", "priority": "medium", "status": "todo"},
    )
    assert update.status_code == 404

    delete = await client.delete(f"/tasks/{task_id}", headers=family["child_headers"])
    assert delete.status_code == 404


@pytest.mark.asyncio
async def test_child_cannot_hide_a_task(client, family):
    response = await create_task(client, family["child_headers"], visibility="parents")

    assert response.status_code == 403
    assert isinstance(response.json()["detail"], str)


@pytest.mark.asyncio
async def test_child_can_still_create_ordinary_task(client, family):
    response = await create_task(client, family["child_headers"], title="Сделать домашку")

    assert response.status_code == 201
    assert response.json()["visibility"] == "family"


@pytest.mark.asyncio
async def test_hidden_task_cannot_be_assigned_to_child(client, family):
    """Иначе задача висела бы на человеке, который её не видит."""
    response = await create_task(
        client,
        family["parent_headers"],
        visibility="parents",
        assignee_id=family["child"]["id"],
    )

    assert response.status_code == 422
    assert "ребёнку" in response.json()["detail"]


@pytest.mark.asyncio
async def test_hiding_a_task_assigned_to_child_is_rejected(client, family):
    """Тот же запрет при правке, а не только при создании."""
    created = await create_task(
        client,
        family["parent_headers"],
        title="Помыть посуду",
        assignee_id=family["child"]["id"],
    )
    task_id = created.json()["id"]

    response = await client.put(
        f"/tasks/{task_id}",
        headers=family["parent_headers"],
        json={
            "title": "Помыть посуду",
            "priority": "medium",
            "status": "todo",
            "assignee_id": family["child"]["id"],
            "visibility": "parents",
        },
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_hidden_task_disappears_from_child_after_change(client, family):
    """Кэш на устройстве ребёнка очистится сам: merge удаляет всё, чего нет в ответе."""
    created = await create_task(client, family["parent_headers"], title="Планы на отпуск")
    task_id = created.json()["id"]

    before = await client.get("/tasks", headers=family["child_headers"])
    assert len(before.json()) == 1

    await client.put(
        f"/tasks/{task_id}",
        headers=family["parent_headers"],
        json={"title": "Планы на отпуск", "priority": "medium", "status": "todo", "visibility": "parents"},
    )

    after = await client.get("/tasks", headers=family["child_headers"])
    assert after.json() == []


@pytest.mark.asyncio
async def test_same_rules_apply_to_notes(client, family):
    await client.post(
        "/notes",
        headers=family["parent_headers"],
        json={"title": "Подарок Соне", "body": "Велосипед", "visibility": "parents"},
    )
    await client.post("/notes", headers=family["parent_headers"], json={"title": "Список покупок"})

    parent_notes = await client.get("/notes", headers=family["parent_headers"])
    assert len(parent_notes.json()) == 2

    child_notes = await client.get("/notes", headers=family["child_headers"])
    assert [n["title"] for n in child_notes.json()] == ["Список покупок"]

    hidden_id = [n for n in parent_notes.json() if n["visibility"] == "parents"][0]["id"]
    direct = await client.delete(f"/notes/{hidden_id}", headers=family["child_headers"])
    assert direct.status_code == 404
