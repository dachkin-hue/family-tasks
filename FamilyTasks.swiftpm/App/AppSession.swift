import Foundation

/// Состояние авторизации на уровне всего приложения.
@Observable
@MainActor
final class AppSession {

    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(UserDTO)
    }

    private(set) var state: State = .checking
    private(set) var isProcessing = false
    var authError: ErrorInfo?

    private let auth: any AuthServicing
    private let tokenStorage: TokenStorage

    init(auth: any AuthServicing, tokenStorage: TokenStorage) {
        self.auth = auth
        self.tokenStorage = tokenStorage
    }

    var currentUser: UserDTO? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    /// Восстановление сессии при холодном старте.
    func restore() async {
        guard await tokenStorage.current() != nil else {
            state = .signedOut
            return
        }
        do {
            let user = try await auth.currentUser()
            state = .signedIn(user)
        } catch {
            await tokenStorage.clear()
            state = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        await perform { try await self.auth.login(email: email, password: password) }
    }

    func register(name: String, email: String, password: String) async {
        await perform { try await self.auth.register(name: name, email: email, password: password) }
    }

    func signOut() async {
        await auth.logout()
        await tokenStorage.clear()
        state = .signedOut
    }

    /// Вызывается из ViewModel, когда сервер ответил 401 и обновить токен не удалось.
    func handleSessionExpired() async {
        await tokenStorage.clear()
        state = .signedOut
        authError = ErrorInfo(
            title: "Сессия истекла",
            message: "Войдите ещё раз, чтобы продолжить.",
            isRetryable: false
        )
    }

    func applyPreviewUser(_ user: UserDTO) {
        state = .signedIn(user)
    }

    private func perform(_ operation: @escaping () async throws -> AuthResult) async {
        isProcessing = true
        authError = nil
        defer { isProcessing = false }
        do {
            let result = try await operation()
            await tokenStorage.save(result.tokens)
            state = .signedIn(result.user)
        } catch {
            authError = ErrorInfo(error)
        }
    }
}
