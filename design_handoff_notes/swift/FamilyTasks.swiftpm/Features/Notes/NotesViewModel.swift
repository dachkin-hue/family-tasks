import Foundation
import SwiftData

/// Фильтр по видимости. Ребёнку не показывается: сервер и так отдаёт ему только общие заметки.
enum NoteFilter: String, CaseIterable, Identifiable {
    case all
    case family
    case parents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .family: return "Общие"
        case .parents: return "Только родители"
        }
    }
}

@MainActor
@Observable
final class NotesViewModel {

    private let repository: NoteRepository
    private let session: AppSession

    private(set) var state: ViewState<[NoteItem]> = .idle
    private(set) var isRefreshing = false
    /// Ошибка операции (создание/удаление) — алертом поверх списка,
    /// в отличие от ошибки загрузки, которая занимает весь экран.
    var operationError: ErrorInfo?

    var filter: NoteFilter = .all {
        didSet { guard oldValue != filter else { return }; applyFilters() }
    }

    var searchText: String = "" {
        didSet { guard oldValue != searchText else { return }; applyFilters() }
    }

    private var allNotes: [NoteItem] = []

    init(repository: NoteRepository, session: AppSession) {
        self.repository = repository
        self.session = session
    }

    var notes: [NoteItem] { state.value ?? [] }

    /// Родитель видит и скрытые заметки, поэтому ему нужен переключатель.
    var showsVisibilityFilter: Bool { session.currentUser?.role == .parent }

    var hiddenCount: Int { allNotes.filter(\.isHiddenFromChildren).count }

    // MARK: - Загрузка

    func onAppear() async {
        guard case .idle = state else { return }

        loadCache()
        if allNotes.isEmpty {
            state = .loading
        }
        await sync(showsSpinner: false)
    }

    func refresh() async {
        await sync(showsSpinner: true)
    }

    func retry() async {
        state = .loading
        await sync(showsSpinner: false)
    }

    private func loadCache() {
        do {
            allNotes = try repository.cachedNotes()
        } catch {
            allNotes = []
        }
        applyFilters()
    }

    private func sync(showsSpinner: Bool) async {
        if showsSpinner { isRefreshing = true }
        defer { isRefreshing = false }

        do {
            allNotes = try await repository.refresh()
            applyFilters()
        } catch {
            await handle(error, allowsFullScreen: allNotes.isEmpty)
        }
    }

    // MARK: - Действия

    /// Короткая заметка — это часто один заголовок, поэтому у списка есть строка быстрой записи.
    func quickCreate(title: String) async {
        do {
            _ = try await repository.create(NoteDraft(title: title, body: nil, visibility: .family))
            loadCache()
        } catch {
            await handle(error, allowsFullScreen: false)
        }
    }

    func create(_ draft: NoteDraft) async throws {
        _ = try await repository.create(draft)
        loadCache()
    }

    func update(_ note: NoteItem, draft: NoteDraft) async throws {
        _ = try await repository.update(note, draft: draft)
        loadCache()
    }

    func delete(_ note: NoteItem) async {
        do {
            try await repository.delete(note)
            loadCache()
        } catch {
            await handle(error, allowsFullScreen: false)
        }
    }

    func reloadFromCache() {
        loadCache()
    }

    func note(withID id: UUID) -> NoteItem? {
        allNotes.first { $0.remoteID == id }
    }

    // MARK: - Фильтрация

    private func applyFilters() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = allNotes.filter { note in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .family: matchesFilter = note.visibility == .family
            case .parents: matchesFilter = note.visibility == .parents
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return note.title.lowercased().contains(query)
                || note.body.lowercased().contains(query)
                || (note.authorName?.lowercased().contains(query) ?? false)
        }

        if case .failed = state, filtered.isEmpty {
            return // не затираем экран ошибки пустым списком
        }
        state = filtered.isEmpty ? .empty : .loaded(filtered)
    }

    private func handle(_ error: Error, allowsFullScreen: Bool) async {
        if let apiError = error as? APIError {
            if case .cancelled = apiError { return }
            if case .unauthorized = apiError {
                await session.handleSessionExpired()
                return
            }
        }

        let info = ErrorInfo(error)
        if allowsFullScreen {
            state = .failed(info)
        } else {
            operationError = info
        }
    }
}
