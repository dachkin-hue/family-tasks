import Foundation

enum TaskPriority: String, Codable, Sendable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Не срочно"
        case .medium: return "Обычный"
        case .high: return "Срочно"
        }
    }

    /// Вес для сортировки: чем больше, тем выше в списке.
    var weight: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}

enum TaskStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case todo
    /// `convertFromSnakeCase` меняет только ключи, но не значения,
    /// поэтому raw value задаём явно под формат Python-бэкенда.
    case inProgress = "in_progress"
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: return "К выполнению"
        case .inProgress: return "В работе"
        case .done: return "Готово"
        }
    }
}

/// Задача в том виде, в котором её отдаёт сервер.
struct TaskDTO: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    var priority: TaskPriority
    var status: TaskStatus
    var assigneeId: UUID?
    var assigneeName: String?
    var createdById: UUID?
    var createdAt: Date
    var updatedAt: Date
}

/// Тело POST /tasks.
struct TaskDraft: Codable, Sendable, Equatable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var priority: TaskPriority
    var assigneeId: UUID?

    static let empty = TaskDraft(title: "", notes: nil, dueDate: nil, priority: .medium, assigneeId: nil)
}

/// Тело PUT /tasks/{id}. Полная замена — никакой неоднозначности «null = не менять».
struct TaskUpdateDTO: Codable, Sendable, Equatable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var priority: TaskPriority
    var status: TaskStatus
    var assigneeId: UUID?

    init(draft: TaskDraft, status: TaskStatus) {
        self.title = draft.title
        self.notes = draft.notes
        self.dueDate = draft.dueDate
        self.priority = draft.priority
        self.status = status
        self.assigneeId = draft.assigneeId
    }
}
