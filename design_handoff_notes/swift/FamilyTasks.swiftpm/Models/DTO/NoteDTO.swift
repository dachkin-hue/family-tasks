import Foundation

/// Кому видна запись. Совпадает с `Visibility` на бэкенде:
/// `parents` детям не отдаётся вовсе, поэтому клиент не обязан её прятать сам.
enum Visibility: String, Codable, Sendable, CaseIterable, Identifiable {
    case family
    case parents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .family: return "Вся семья"
        case .parents: return "Только родители"
        }
    }

    var shortTitle: String {
        switch self {
        case .family: return "Общая"
        case .parents: return "Родители"
        }
    }
}

/// Заметка в том виде, в котором её отдаёт сервер: без сроков, статусов и исполнителей.
struct NoteDTO: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var body: String?
    var visibility: Visibility
    var authorId: UUID?
    var authorName: String?
    var createdAt: Date
    var updatedAt: Date
}

/// Тело POST /notes и PUT /notes/{id} — PUT является полной заменой, как и у задач.
/// Автора сервер не переписывает: это тот, кто завёл заметку.
struct NoteDraft: Codable, Sendable, Equatable {
    var title: String
    var body: String?
    var visibility: Visibility

    static let empty = NoteDraft(title: "", body: nil, visibility: .family)
}
