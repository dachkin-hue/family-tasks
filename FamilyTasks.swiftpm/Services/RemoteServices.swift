import Foundation

// MARK: - Auth

struct RemoteAuthService: AuthServicing {

    let api: any APIClient
    let tokenStorage: TokenStorage

    func login(email: String, password: String) async throws -> AuthResult {
        let response: AuthResponseDTO = try await api.send(try .login(email: email, password: password))
        return response.result
    }

    func register(name: String, email: String, password: String) async throws -> AuthResult {
        let response: AuthResponseDTO = try await api.send(try .register(name: name, email: email, password: password))
        return response.result
    }

    func currentUser() async throws -> UserDTO {
        try await api.send(.me)
    }

    func logout() async {
        // Ошибку намеренно глотаем: локальный выход должен произойти в любом случае.
        try? await api.sendIgnoringResponse(.logout)
    }
}

// MARK: - Tasks

struct RemoteTaskService: TaskServicing {

    let api: any APIClient

    func fetchTasks() async throws -> [TaskDTO] {
        try await api.send(.tasks)
    }

    func createTask(_ draft: TaskDraft) async throws -> TaskDTO {
        try await api.send(try .createTask(draft))
    }

    func updateTask(id: UUID, draft: TaskDraft, status: TaskStatus) async throws -> TaskDTO {
        let payload = TaskUpdateDTO(draft: draft, status: status)
        return try await api.send(try .updateTask(id: id, payload: payload))
    }

    func deleteTask(id: UUID) async throws {
        try await api.sendIgnoringResponse(.deleteTask(id: id))
    }
}

// MARK: - Family

struct RemoteMemberService: MemberServicing {

    let api: any APIClient

    func fetchMembers() async throws -> [UserDTO] {
        try await api.send(.members)
    }
}
