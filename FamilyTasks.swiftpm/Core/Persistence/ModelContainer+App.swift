import Foundation
import SwiftData

extension ModelContainer {

    /// Единая точка создания хранилища.
    /// Кэш можно безопасно уронить: при первом запуске после несовместимой миграции
    /// файл пересоздаётся, данные всё равно приедут с сервера.
    static func makeAppContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([TaskItem.self, NoteItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Схема кэша изменилась — сносим локальный файл и начинаем заново.
            deleteStoreFiles()
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Не удалось создать ModelContainer: \(error)")
            }
        }
    }

    private static func deleteStoreFiles() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: support.appending(path: name))
        }
    }
}
