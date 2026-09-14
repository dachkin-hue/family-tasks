import Foundation

/// Карта эндпоинтов заметок. Вынесена отдельным расширением,
/// чтобы `APIEndpoint.swift` не пришлось править при добавлении раздела.
extension APIEndpoint {

    // MARK: - Notes

    static var notes: APIEndpoint {
        APIEndpoint(path: "notes")
    }

    static func createNote(_ draft: NoteDraft) throws -> APIEndpoint {
        APIEndpoint(path: "notes", method: .post, body: try JSONCoding.encode(draft))
    }

    static func updateNote(id: UUID, draft: NoteDraft) throws -> APIEndpoint {
        APIEndpoint(path: "notes/\(id.uuidString)", method: .put, body: try JSONCoding.encode(draft))
    }

    static func deleteNote(id: UUID) -> APIEndpoint {
        APIEndpoint(path: "notes/\(id.uuidString)", method: .delete)
    }
}
