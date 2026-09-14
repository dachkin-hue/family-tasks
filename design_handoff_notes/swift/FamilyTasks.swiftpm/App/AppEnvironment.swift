import Foundation
import SwiftData

/// Контейнер зависимостей приложения.
/// Собирается один раз на старте и раздаётся во View через `.environment(_:)`.
@Observable
@MainActor
final class AppEnvironment {

    let modelContainer: ModelContainer
    let session: AppSession
    let taskService: any TaskServicing
    let noteService: any NoteServicing
    let memberService: any MemberServicing

    private init(
        modelContainer: ModelContainer,
        session: AppSession,
        taskService: any TaskServicing,
        noteService: any NoteServicing,
        memberService: any MemberServicing
    ) {
        self.modelContainer = modelContainer
        self.session = session
        self.taskService = taskService
        self.noteService = noteService
        self.memberService = memberService
    }

    // MARK: - Сборка

    static func live() -> AppEnvironment {
        let container = ModelContainer.makeAppContainer(inMemory: false)
        let tokenStorage = TokenStorage(service: AppConfig.keychainService)

        if AppConfig.useMockBackend {
            let backend = MockBackend()
            return AppEnvironment(
                modelContainer: container,
                session: AppSession(auth: MockAuthService(backend: backend), tokenStorage: tokenStorage),
                taskService: MockTaskService(backend: backend),
                noteService: MockNoteService(backend: MockNotesBackend()),
                memberService: MockMemberService(backend: backend)
            )
        } else {
            let api = NetworkManager(baseURL: AppConfig.baseURL, tokenStorage: tokenStorage)
            return AppEnvironment(
                modelContainer: container,
                session: AppSession(auth: RemoteAuthService(api: api, tokenStorage: tokenStorage), tokenStorage: tokenStorage),
                taskService: RemoteTaskService(api: api),
                noteService: RemoteNoteService(api: api),
                memberService: RemoteMemberService(api: api)
            )
        }
    }

    /// Окружение для SwiftUI-превью: база в памяти, моки, пользователь уже авторизован.
    static func preview() -> AppEnvironment {
        let container = ModelContainer.makeAppContainer(inMemory: true)
        let backend = MockBackend()
        let session = AppSession(auth: MockAuthService(backend: backend), tokenStorage: TokenStorage(service: "preview"))
        session.applyPreviewUser(UserDTO.previewParent)
        return AppEnvironment(
            modelContainer: container,
            session: session,
            taskService: MockTaskService(backend: backend),
            noteService: MockNoteService(backend: MockNotesBackend()),
            memberService: MockMemberService(backend: backend)
        )
    }

    // MARK: - Фабрики

    /// Репозиторий работает с `mainContext`: объёмы семейного списка небольшие,
    /// а вся работа с UI остаётся на главном акторе без гонок за `ModelContext`.
    func makeTaskRepository() -> TaskRepository {
        TaskRepository(service: taskService, context: modelContainer.mainContext)
    }

    func makeNoteRepository() -> NoteRepository {
        NoteRepository(service: noteService, context: modelContainer.mainContext)
    }
}
