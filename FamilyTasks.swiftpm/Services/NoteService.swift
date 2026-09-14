import Foundation

/// Контракт раздела заметок. Как и у задач, ViewModel знает только о протоколе —
/// выбор мок/боевой реализации происходит в `AppEnvironment`.
protocol NoteServicing: Sendable {
    func fetchNotes() async throws -> [NoteDTO]
    func createNote(_ draft: NoteDraft) async throws -> NoteDTO
    func updateNote(id: UUID, draft: NoteDraft) async throws -> NoteDTO
    func deleteNote(id: UUID) async throws
}

// MARK: - Боевой сервис

struct RemoteNoteService: NoteServicing {

    let api: any APIClient

    func fetchNotes() async throws -> [NoteDTO] {
        try await api.send(.notes)
    }

    func createNote(_ draft: NoteDraft) async throws -> NoteDTO {
        try await api.send(try .createNote(draft))
    }

    func updateNote(id: UUID, draft: NoteDraft) async throws -> NoteDTO {
        try await api.send(try .updateNote(id: id, draft: draft))
    }

    func deleteNote(id: UUID) async throws {
        try await api.sendIgnoringResponse(.deleteNote(id: id))
    }
}

// MARK: - Мок

/// Отдельный актор, а не расширение `MockBackend`: раздел заметок ничего не знает
/// о задачах и авторизации, поэтому его состояние живёт само по себе.
actor MockNotesBackend {

    /// Поставьте `true`, чтобы проверить экраны ошибок.
    var shouldFail = false
    var latency: Duration = .milliseconds(500)

    /// Кем «подписаны» правки в моке. По умолчанию — тот же пользователь, что и в `MockBackend`.
    private var currentUser: UserDTO = .previewParent
    private var notes: [NoteDTO] = MockNotesBackend.seed()

    func setShouldFail(_ value: Bool) { shouldFail = value }
    func setLatency(_ value: Duration) { latency = value }
    func setCurrentUser(_ user: UserDTO) { currentUser = user }

    func fetchNotes() async throws -> [NoteDTO] {
        try await wait()
        // Повторяем правила сервера: детям заметки «только родители» не отдаются,
        // недавно изменённые идут первыми.
        return notes
            .filter { currentUser.role == .parent || $0.visibility == .family }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createNote(_ draft: NoteDraft) async throws -> NoteDTO {
        try await wait()
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw APIError.validation(message: "Укажите заголовок заметки.")
        }
        let now = Date()
        let note = NoteDTO(
            id: UUID(),
            title: title,
            body: draft.body,
            visibility: draft.visibility,
            authorId: currentUser.id,
            authorName: currentUser.name,
            createdAt: now,
            updatedAt: now
        )
        notes.insert(note, at: 0)
        return note
    }

    func updateNote(id: UUID, draft: NoteDraft) async throws -> NoteDTO {
        try await wait()
        guard let index = notes.firstIndex(where: { $0.id == id }) else { throw APIError.notFound }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw APIError.validation(message: "Укажите заголовок заметки.")
        }
        // Автора намеренно не трогаем: общая заметка — блокнот семьи,
        // её может править любой, но завёл её кто-то один.
        notes[index].title = title
        notes[index].body = draft.body
        notes[index].visibility = draft.visibility
        notes[index].updatedAt = Date()
        return notes[index]
    }

    func deleteNote(id: UUID) async throws {
        try await wait()
        guard notes.contains(where: { $0.id == id }) else { throw APIError.notFound }
        notes.removeAll { $0.id == id }
    }

    private func wait() async throws {
        try? await Task.sleep(for: latency)
        if shouldFail {
            throw APIError.server(status: 503, message: "Сервер недоступен (имитация).")
        }
    }

    private static func seed() -> [NoteDTO] {
        let now = Date()

        func ago(_ minutes: Int) -> Date { now.addingTimeInterval(-Double(minutes) * 60) }

        func note(
            _ title: String,
            _ body: String?,
            _ visibility: Visibility,
            author: UserDTO,
            updated: Date
        ) -> NoteDTO {
            NoteDTO(
                id: UUID(),
                title: title,
                body: body,
                visibility: visibility,
                authorId: author.id,
                authorName: author.name,
                createdAt: updated,
                updatedAt: updated
            )
        }

        return [
            note(
                "Что купить в «Метро»",
                "Крупы, кофе в зёрнах, стиральный порошок.\nБольшую упаковку кошачьего корма.",
                .family, author: .previewPartner, updated: ago(30)
            ),
            note(
                "Размеры детей",
                "Соня — обувь 37, куртка 152.\nШкольные брюки: рост 152, пояс 64.",
                .family, author: .previewParent, updated: ago(240)
            ),
            note(
                "Подарок Соне на день рождения",
                "Наушники или сертификат в книжный. Спросить у Иры, что она дарит.",
                .parents, author: .previewPartner, updated: ago(1020)
            ),
            note(
                "Телефон школы и секции",
                "Школа, канцелярия — 8 (343) 000-11-22.\nТренер Игорь — 8 (912) 000-33-44.",
                .family, author: .previewParent, updated: ago(2880)
            ),
            note("Позвонить в поликлинику", nil, .family, author: .previewChild, updated: ago(4320))
        ]
    }
}

struct MockNoteService: NoteServicing {
    let backend: MockNotesBackend

    func fetchNotes() async throws -> [NoteDTO] {
        try await backend.fetchNotes()
    }

    func createNote(_ draft: NoteDraft) async throws -> NoteDTO {
        try await backend.createNote(draft)
    }

    func updateNote(id: UUID, draft: NoteDraft) async throws -> NoteDTO {
        try await backend.updateNote(id: id, draft: draft)
    }

    func deleteNote(id: UUID) async throws {
        try await backend.deleteNote(id: id)
    }
}
