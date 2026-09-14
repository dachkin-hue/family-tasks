import Foundation
import SwiftData

/// Посредник между сервисом заметок и кэшем. Стратегия та же, что у `TaskRepository`:
/// сервер — источник истины, база нужна для мгновенного показа и офлайн-чтения.
@MainActor
final class NoteRepository {

    private let service: any NoteServicing
    private let context: ModelContext

    init(service: any NoteServicing, context: ModelContext) {
        self.service = service
        self.context = context
    }

    // MARK: - Чтение кэша

    func cachedNotes() throws -> [NoteItem] {
        let items = try context.fetch(FetchDescriptor<NoteItem>())
        return Self.sorted(items)
    }

    // MARK: - Синхронизация

    @discardableResult
    func refresh() async throws -> [NoteItem] {
        let remote = try await service.fetchNotes()
        try merge(remote)
        return try cachedNotes()
    }

    // MARK: - Изменения

    @discardableResult
    func create(_ draft: NoteDraft) async throws -> NoteItem {
        let dto = try await service.createNote(draft)
        return try upsert(dto)
    }

    @discardableResult
    func update(_ note: NoteItem, draft: NoteDraft) async throws -> NoteItem {
        let dto = try await service.updateNote(id: note.remoteID, draft: draft)
        return try upsert(dto)
    }

    func delete(_ note: NoteItem) async throws {
        let id = note.remoteID
        try await service.deleteNote(id: id)
        if let local = try find(id) {
            context.delete(local)
            try context.save()
        }
    }

    // MARK: - Внутреннее

    private func merge(_ dtos: [NoteDTO]) throws {
        let existing = try context.fetch(FetchDescriptor<NoteItem>())
        var index = Dictionary(existing.map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })

        for dto in dtos {
            if let item = index.removeValue(forKey: dto.id) {
                item.apply(dto)
            } else {
                context.insert(NoteItem(dto: dto))
            }
        }

        // Чего нет на сервере — нет и в кэше. В том числе заметок,
        // которые стали «только для родителей» и перестали приходить ребёнку.
        for orphan in index.values {
            context.delete(orphan)
        }

        try context.save()
    }

    @discardableResult
    private func upsert(_ dto: NoteDTO) throws -> NoteItem {
        let item: NoteItem
        if let existing = try find(dto.id) {
            existing.apply(dto)
            item = existing
        } else {
            item = NoteItem(dto: dto)
            context.insert(item)
        }
        try context.save()
        return item
    }

    private func find(_ id: UUID) throws -> NoteItem? {
        var descriptor = FetchDescriptor<NoteItem>(predicate: #Predicate { $0.remoteID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Недавно изменённые сверху — тот же порядок, что отдаёт GET /notes.
    private static func sorted(_ items: [NoteItem]) -> [NoteItem] {
        items.sorted { $0.updatedAt > $1.updatedAt }
    }
}
