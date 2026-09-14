"""Заметки: тот же контракт, что у задач, только проще."""

import re

import pytest

ISO_WITH_TZ = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:\d{2}|Z)$")


@pytest.mark.asyncio
async def test_note_crud(client, family):
    headers = family["parent_headers"]

    created = await client.post(
        "/notes",
        headers=headers,
        json={"title": "Список покупок", "body": "Молоко, хлеб, кофе"},
    )
    assert created.status_code == 201, created.text
    note = created.json()

    assert set(note) == {
        "id", "title", "body", "visibility",
        "author_id", "author_name", "created_at", "updated_at",
    }
    assert note["author_name"] == "Александр"
    assert note["visibility"] == "family"
    for field in ("created_at", "updated_at"):
        assert ISO_WITH_TZ.match(note[field]), f"{field} = {note[field]}"

    listed = await client.get("/notes", headers=headers)
    assert len(listed.json()) == 1

    updated = await client.put(
        f"/notes/{note['id']}",
        headers=headers,
        json={"title": "Список покупок", "body": "Молоко, хлеб, кофе, сыр"},
    )
    assert updated.status_code == 200
    assert updated.json()["body"].endswith("сыр")

    deleted = await client.delete(f"/notes/{note['id']}", headers=headers)
    assert deleted.status_code == 204
    assert (await client.get("/notes", headers=headers)).json() == []


@pytest.mark.asyncio
async def test_note_without_body(client, family):
    """Короткая заметка — это часто один заголовок."""
    response = await client.post(
        "/notes", headers=family["parent_headers"], json={"title": "Позвонить в школу"}
    )

    assert response.status_code == 201
    assert response.json()["body"] is None


@pytest.mark.asyncio
async def test_empty_title_is_rejected(client, family):
    response = await client.post("/notes", headers=family["parent_headers"], json={"title": ""})

    assert response.status_code == 422
    assert isinstance(response.json()["detail"], list)


@pytest.mark.asyncio
async def test_child_can_edit_family_note(client, family):
    """Общая заметка — это блокнот семьи, а не личная запись автора."""
    created = await client.post(
        "/notes", headers=family["parent_headers"], json={"title": "Что купить"}
    )
    note_id = created.json()["id"]

    updated = await client.put(
        f"/notes/{note_id}",
        headers=family["child_headers"],
        json={"title": "Что купить", "body": "И мороженое"},
    )
    assert updated.status_code == 200
    # Автор остаётся тем, кто завёл заметку.
    assert updated.json()["author_name"] == "Александр"


@pytest.mark.asyncio
async def test_notes_of_another_family_are_invisible(client, family):
    stranger = (
        await client.post(
            "/auth/register",
            json={"name": "Чужой", "email": "other@example.com", "password": "secret"},
        )
    ).json()
    stranger_headers = {"Authorization": f"Bearer {stranger['access_token']}"}

    created = await client.post(
        "/notes", headers=family["parent_headers"], json={"title": "Семейное"}
    )
    note_id = created.json()["id"]

    assert (await client.get("/notes", headers=stranger_headers)).json() == []
    assert (await client.delete(f"/notes/{note_id}", headers=stranger_headers)).status_code == 404


@pytest.mark.asyncio
async def test_notes_require_authorization(client):
    assert (await client.get("/notes")).status_code == 401


@pytest.mark.asyncio
async def test_recently_updated_notes_come_first(client, family):
    headers = family["parent_headers"]

    first = await client.post("/notes", headers=headers, json={"title": "Первая"})
    await client.post("/notes", headers=headers, json={"title": "Вторая"})

    await client.put(
        f"/notes/{first.json()['id']}", headers=headers, json={"title": "Первая", "body": "правка"}
    )

    listed = await client.get("/notes", headers=headers)
    assert [n["title"] for n in listed.json()] == ["Первая", "Вторая"]
