import Foundation
import SwiftData

/// Локальная копия задачи (кэш). Источник истины — сервер,
/// поэтому здесь нет флагов «не синхронизировано»: всё, что пришло с сервера, перезаписывает локальное.
@Model
final class TaskItem {

    /// Идентификатор с сервера. Уникален — по нему идёт слияние.
    @Attribute(.unique) var remoteID: UUID

    var title: String
    var notes: String
    var dueDate: Date?
    var assigneeID: UUID?
    /// Имя исполнителя денормализовано, чтобы список не зависел от загрузки участников.
    var assigneeName: String?
    var createdByID: UUID?
    var createdAt: Date
    var updatedAt: Date

    /// SwiftData хранит примитив, наружу отдаём типизированный enum.
    var priorityRaw: String
    var statusRaw: String

    init(dto: TaskDTO) {
        self.remoteID = dto.id
        self.title = dto.title
        self.notes = dto.notes ?? ""
        self.dueDate = dto.dueDate
        self.assigneeID = dto.assigneeId
        self.assigneeName = dto.assigneeName
        self.createdByID = dto.createdById
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
        self.priorityRaw = dto.priority.rawValue
        self.statusRaw = dto.status.rawValue
    }

    // MARK: - Типизированный доступ

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var isCompleted: Bool { status == .done }

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    // MARK: - Преобразования

    func apply(_ dto: TaskDTO) {
        title = dto.title
        notes = dto.notes ?? ""
        dueDate = dto.dueDate
        assigneeID = dto.assigneeId
        assigneeName = dto.assigneeName
        createdByID = dto.createdById
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        priorityRaw = dto.priority.rawValue
        statusRaw = dto.status.rawValue
    }

    var draft: TaskDraft {
        TaskDraft(
            title: title,
            notes: notes.isEmpty ? nil : notes,
            dueDate: dueDate,
            priority: priority,
            assigneeId: assigneeID
        )
    }
}
