import Foundation
import SwiftData

/// Локальная копия заметки (кэш). Источник истины — сервер,
/// поэтому флагов «не синхронизировано» здесь нет: пришедшее с сервера перезаписывает локальное.
@Model
final class NoteItem {

    @Attribute(.unique) var remoteID: UUID

    var title: String
    var body: String
    /// Имя автора денормализовано, чтобы список не зависел от загрузки участников.
    var authorID: UUID?
    var authorName: String?
    var createdAt: Date
    var updatedAt: Date

    /// SwiftData хранит примитив, наружу отдаём типизированный enum.
    var visibilityRaw: String

    init(dto: NoteDTO) {
        self.remoteID = dto.id
        self.title = dto.title
        self.body = dto.body ?? ""
        self.authorID = dto.authorId
        self.authorName = dto.authorName
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
        self.visibilityRaw = dto.visibility.rawValue
    }

    var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .family }
        set { visibilityRaw = newValue.rawValue }
    }

    var isHiddenFromChildren: Bool { visibility == .parents }

    func apply(_ dto: NoteDTO) {
        title = dto.title
        body = dto.body ?? ""
        authorID = dto.authorId
        authorName = dto.authorName
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        visibilityRaw = dto.visibility.rawValue
    }

    var draft: NoteDraft {
        NoteDraft(title: title, body: body.isEmpty ? nil : body, visibility: visibility)
    }
}
