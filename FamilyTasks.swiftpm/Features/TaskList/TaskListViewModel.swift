import Foundation
import SwiftData

enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case mine
    case today
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .mine: return "Мои"
        case .today: return "Сегодня"
        case .done: return "Готово"
        }
    }
}

@MainActor
@Observable
final class TaskListViewModel {

    private let repository: TaskRepository
    private let session: AppSession

    private(set) var state: ViewState<[TaskItem]> = .idle
    private(set) var isRefreshing = false
    /// Ошибка операции (создание/удаление/смена статуса) — показывается алертом поверх списка,
    /// в отличие от ошибки загрузки, которая занимает весь экран.
    var operationError: ErrorInfo?

    var filter: TaskFilter = .all {
        didSet { guard oldValue != filter else { return }; applyFilters() }
    }

    var searchText: String = "" {
        didSet { guard oldValue != searchText else { return }; applyFilters() }
    }

    /// Все задачи из кэша до фильтрации — фильтры применяем в памяти, без похода в базу.
    private var allTasks: [TaskItem] = []

    init(repository: TaskRepository, session: AppSession) {
        self.repository = repository
        self.session = session
    }

    var tasks: [TaskItem] { state.value ?? [] }

    var openCount: Int { allTasks.filter { !$0.isCompleted }.count }

    // MARK: - Загрузка

    /// Сначала показываем кэш, затем тихо обновляем с сервера.
    func onAppear() async {
        guard case .idle = state else { return }

        loadCache()
        if allTasks.isEmpty {
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
            allTasks = try repository.cachedTasks()
        } catch {
            allTasks = []
        }
        applyFilters()
    }

    private func sync(showsSpinner: Bool) async {
        if showsSpinner { isRefreshing = true }
        defer { isRefreshing = false }

        do {
            allTasks = try await repository.refresh()
            applyFilters()
        } catch {
            await handle(error, allowsFullScreen: allTasks.isEmpty)
        }
    }

    // MARK: - Действия

    func toggleCompletion(_ task: TaskItem) async {
        let newStatus: TaskStatus = task.isCompleted ? .todo : .done
        do {
            _ = try await repository.setStatus(newStatus, for: task)
            loadCache()
        } catch {
            await handle(error, allowsFullScreen: false)
        }
    }

    func advanceStatus(_ task: TaskItem) async {
        let next: TaskStatus
        switch task.status {
        case .todo: next = .inProgress
        case .inProgress: next = .done
        case .done: next = .todo
        }
        do {
            _ = try await repository.setStatus(next, for: task)
            loadCache()
        } catch {
            await handle(error, allowsFullScreen: false)
        }
    }

    func delete(_ task: TaskItem) async {
        do {
            try await repository.delete(task)
            loadCache()
        } catch {
            await handle(error, allowsFullScreen: false)
        }
    }

    func create(_ draft: TaskDraft) async throws {
        _ = try await repository.create(draft)
        loadCache()
    }

    func update(_ task: TaskItem, draft: TaskDraft, status: TaskStatus) async throws {
        _ = try await repository.update(task, draft: draft, status: status)
        loadCache()
    }

    /// Вызывается после редактирования задачи на экране деталей.
    func reloadFromCache() {
        loadCache()
    }

    /// Навигация идёт по идентификатору, а не по объекту модели:
    /// так стек не ломается, если задачу удалили или перезагрузили из сети.
    func task(withID id: UUID) -> TaskItem? {
        allTasks.first { $0.remoteID == id }
    }

    // MARK: - Фильтрация

    private func applyFilters() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let currentUserID = session.currentUser?.id

        let filtered = allTasks.filter { task in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = !task.isCompleted
            case .mine:
                matchesFilter = !task.isCompleted && task.assigneeID == currentUserID
            case .today:
                matchesFilter = !task.isCompleted && (task.isDueToday || task.isOverdue)
            case .done:
                matchesFilter = task.isCompleted
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return task.title.lowercased().contains(query)
                || task.notes.lowercased().contains(query)
                || (task.assigneeName?.lowercased().contains(query) ?? false)
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
