import Foundation

/// Контракты сервисов. ViewModel и репозиторий знают только о них —
/// переключение мок/боевой бэкенд происходит в `AppEnvironment` и больше нигде.

protocol AuthServicing: Sendable {
    func login(email: String, password: String) async throws -> AuthResult
    func register(name: String, email: String, password: String) async throws -> AuthResult
    func currentUser() async throws -> UserDTO
    func logout() async
}

protocol TaskServicing: Sendable {
    func fetchTasks() async throws -> [TaskDTO]
    func createTask(_ draft: TaskDraft) async throws -> TaskDTO
    func updateTask(id: UUID, draft: TaskDraft, status: TaskStatus) async throws -> TaskDTO
    func deleteTask(id: UUID) async throws
}

protocol MemberServicing: Sendable {
    func fetchMembers() async throws -> [UserDTO]
}
