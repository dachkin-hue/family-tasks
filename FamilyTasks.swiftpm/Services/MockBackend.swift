import Foundation

/// Имитация будущего сервера: живёт в памяти, отвечает с задержкой,
/// умеет ошибаться по требованию. Позволяет разрабатывать и тестировать UI до деплоя VPS.
actor MockBackend {

    /// Поставьте `true`, чтобы проверить экраны ошибок.
    var shouldFail = false
    /// Искусственная задержка сети.
    var latency: Duration = .milliseconds(600)

    private(set) var members: [UserDTO] = [.previewParent, .previewPartner, .previewChild]
    private(set) var currentUser: UserDTO = .previewParent
    private var tasks: [TaskDTO] = MockBackend.seedTasks()

    /// Счётчик неудачных входов — как на сервере, только в памяти мока.
    private var failedLogins: [String: Int] = [:]
    private static let maxFailedLogins = 5

    // MARK: - Настройка

    func setShouldFail(_ value: Bool) { shouldFail = value }
    func setLatency(_ value: Duration) { latency = value }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> AuthResult {
        try await wait()

        // Повторяем поведение бэкенда, чтобы экран блокировки
        // можно было увидеть без сервера.
        if failedLogins[email, default: 0] >= Self.maxFailedLogins {
            throw APIError.tooManyRequests(
                message: "Слишком много попыток входа. Повторите через 15 мин.",
                retryAfter: 900
            )
        }

        guard password.count >= 4 else {
            failedLogins[email, default: 0] += 1
            throw APIError.validation(message: "Пароль должен быть не короче 4 символов.")
        }

        failedLogins[email] = nil
        currentUser = UserDTO(
            id: currentUser.id,
            name: currentUser.name,
            email: email,
            role: .parent,
            colorHex: currentUser.colorHex
        )
        return AuthResult(tokens: Self.makeTokens(), user: currentUser)
    }

    func register(name: String, email: String, password: String) async throws -> AuthResult {
        try await wait()
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw APIError.validation(message: "Укажите имя.")
        }
        guard password.count >= 4 else {
            throw APIError.validation(message: "Пароль должен быть не короче 4 символов.")
        }
        let user = UserDTO(id: UUID(), name: name, email: email, role: .parent, colorHex: "#6366F1")
        currentUser = user
        members.insert(user, at: 0)
        return AuthResult(tokens: Self.makeTokens(), user: user)
    }

    /// Мок принимает любой сохранённый токен: после перезапуска приложения
    /// сессия восстанавливается так же, как это будет делать настоящий /me.
    func me() async throws -> UserDTO {
        try await wait()
        return currentUser
    }

    // MARK: - Tasks

    func fetchTasks() async throws -> [TaskDTO] {
        try await wait()
        return tasks
    }

    func createTask(_ draft: TaskDraft) async throws -> TaskDTO {
        try await wait()
        let now = Date()
        let dto = TaskDTO(
            id: UUID(),
            title: draft.title,
            notes: draft.notes,
            dueDate: draft.dueDate,
            priority: draft.priority,
            status: .todo,
            assigneeId: draft.assigneeId,
            assigneeName: name(for: draft.assigneeId),
            createdById: currentUser.id,
            createdAt: now,
            updatedAt: now
        )
        tasks.append(dto)
        return dto
    }

    func updateTask(id: UUID, draft: TaskDraft, status: TaskStatus) async throws -> TaskDTO {
        try await wait()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound
        }
        var dto = tasks[index]
        dto.title = draft.title
        dto.notes = draft.notes
        dto.dueDate = draft.dueDate
        dto.priority = draft.priority
        dto.status = status
        dto.assigneeId = draft.assigneeId
        dto.assigneeName = name(for: draft.assigneeId)
        dto.updatedAt = Date()
        tasks[index] = dto
        return dto
    }

    func deleteTask(id: UUID) async throws {
        try await wait()
        guard tasks.contains(where: { $0.id == id }) else { throw APIError.notFound }
        tasks.removeAll { $0.id == id }
    }

    func fetchMembers() async throws -> [UserDTO] {
        try await wait()
        return members
    }

    // MARK: - Вспомогательное

    private func wait() async throws {
        try? await Task.sleep(for: latency)
        if shouldFail {
            throw APIError.server(status: 503, message: "Сервер недоступен (имитация).")
        }
    }

    private func name(for id: UUID?) -> String? {
        guard let id else { return nil }
        return members.first { $0.id == id }?.name
    }

    private static func makeTokens() -> AuthTokens {
        AuthTokens(
            accessToken: "mock-access-\(UUID().uuidString)",
            refreshToken: "mock-refresh-\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    private static func seedTasks() -> [TaskDTO] {
        let calendar = Calendar.current
        let now = Date()

        func date(_ days: Int, hour: Int) -> Date {
            let shifted = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shifted) ?? shifted
        }

        return [
            TaskDTO(
                id: UUID(), title: "Забрать Соню с тренировки",
                notes: "Секция заканчивается в 18:30, вход со двора.",
                dueDate: date(0, hour: 18), priority: .high, status: .todo,
                assigneeId: UserDTO.previewParent.id, assigneeName: UserDTO.previewParent.name,
                createdById: UserDTO.previewPartner.id, createdAt: now, updatedAt: now
            ),
            TaskDTO(
                id: UUID(), title: "Купить продукты на неделю",
                notes: "Молоко, хлеб, овощи, корм коту.",
                dueDate: date(0, hour: 20), priority: .medium, status: .inProgress,
                assigneeId: UserDTO.previewPartner.id, assigneeName: UserDTO.previewPartner.name,
                createdById: UserDTO.previewParent.id, createdAt: now, updatedAt: now
            ),
            TaskDTO(
                id: UUID(), title: "Сделать домашку по математике",
                notes: nil,
                dueDate: date(1, hour: 19), priority: .high, status: .todo,
                assigneeId: UserDTO.previewChild.id, assigneeName: UserDTO.previewChild.name,
                createdById: UserDTO.previewPartner.id, createdAt: now, updatedAt: now
            ),
            TaskDTO(
                id: UUID(), title: "Записать машину на ТО",
                notes: "Сервис на Ленина, спросить про замену колодок.",
                dueDate: date(4, hour: 12), priority: .low, status: .todo,
                assigneeId: UserDTO.previewParent.id, assigneeName: UserDTO.previewParent.name,
                createdById: UserDTO.previewParent.id, createdAt: now, updatedAt: now
            ),
            TaskDTO(
                id: UUID(), title: "Оплатить коммуналку",
                notes: nil,
                dueDate: date(-2, hour: 10), priority: .medium, status: .done,
                assigneeId: UserDTO.previewPartner.id, assigneeName: UserDTO.previewPartner.name,
                createdById: UserDTO.previewPartner.id, createdAt: now, updatedAt: now
            )
        ]
    }
}

// MARK: - Сервисы поверх мока

struct MockAuthService: AuthServicing {
    let backend: MockBackend

    func login(email: String, password: String) async throws -> AuthResult {
        try await backend.login(email: email, password: password)
    }

    func register(name: String, email: String, password: String) async throws -> AuthResult {
        try await backend.register(name: name, email: email, password: password)
    }

    func currentUser() async throws -> UserDTO {
        try await backend.me()
    }

    func logout() async {}
}

struct MockTaskService: TaskServicing {
    let backend: MockBackend

    func fetchTasks() async throws -> [TaskDTO] {
        try await backend.fetchTasks()
    }

    func createTask(_ draft: TaskDraft) async throws -> TaskDTO {
        try await backend.createTask(draft)
    }

    func updateTask(id: UUID, draft: TaskDraft, status: TaskStatus) async throws -> TaskDTO {
        try await backend.updateTask(id: id, draft: draft, status: status)
    }

    func deleteTask(id: UUID) async throws {
        try await backend.deleteTask(id: id)
    }
}

struct MockMemberService: MemberServicing {
    let backend: MockBackend

    func fetchMembers() async throws -> [UserDTO] {
        try await backend.fetchMembers()
    }
}
