import Foundation
import SwiftData

/// Посредник между сервисом (сеть) и кэшем (SwiftData).
/// Стратегия: сервер — источник истины, локальная база нужна для мгновенного показа и офлайн-чтения.
@MainActor
final class TaskRepository {

    private let service: any TaskServicing
    private let context: ModelContext

    init(service: any TaskServicing, context: ModelContext) {
        self.service = service
        self.context = context
    }

    // MARK: - Чтение кэша

    func cachedTasks() throws -> [TaskItem] {
        let items = try context.fetch(FetchDescriptor<TaskItem>())
        return Self.sorted(items)
    }

    // MARK: - Синхронизация

    /// Полная перезагрузка списка с сервера с последующим слиянием в кэш.
    @discardableResult
    func refresh() async throws -> [TaskItem] {
        let remote = try await service.fetchTasks()
        try merge(remote)
        return try cachedTasks()
    }

    // MARK: - Изменения

    @discardableResult
    func create(_ draft: TaskDraft) async throws -> TaskItem {
        let dto = try await service.createTask(draft)
        return try upsert(dto)
    }

    @discardableResult
    func update(_ task: TaskItem, draft: TaskDraft, status: TaskStatus) async throws -> TaskItem {
        let dto = try await service.updateTask(id: task.remoteID, draft: draft, status: status)
        return try upsert(dto)
    }

    @discardableResult
    func setStatus(_ status: TaskStatus, for task: TaskItem) async throws -> TaskItem {
        try await update(task, draft: task.draft, status: status)
    }

    func delete(_ task: TaskItem) async throws {
        let id = task.remoteID
        try await service.deleteTask(id: id)
        if let local = try find(id) {
            context.delete(local)
            try context.save()
        }
    }

    // MARK: - Внутреннее

    private func merge(_ dtos: [TaskDTO]) throws {
        let existing = try context.fetch(FetchDescriptor<TaskItem>())
        var index = Dictionary(existing.map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })

        for dto in dtos {
            if let item = index.removeValue(forKey: dto.id) {
                item.apply(dto)
            } else {
                context.insert(TaskItem(dto: dto))
            }
        }

        // Всё, чего нет на сервере, в кэше тоже быть не должно.
        for orphan in index.values {
            context.delete(orphan)
        }

        try context.save()
    }

    @discardableResult
    private func upsert(_ dto: TaskDTO) throws -> TaskItem {
        let item: TaskItem
        if let existing = try find(dto.id) {
            existing.apply(dto)
            item = existing
        } else {
            item = TaskItem(dto: dto)
            context.insert(item)
        }
        try context.save()
        return item
    }

    private func find(_ id: UUID) throws -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.remoteID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Сортировка в памяти: невыполненные выше, затем по сроку, затем по важности.
    private static func sorted(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                break
            }
            if lhs.priority.weight != rhs.priority.weight {
                return lhs.priority.weight > rhs.priority.weight
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
