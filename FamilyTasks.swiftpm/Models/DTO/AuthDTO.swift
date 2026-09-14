import Foundation

// MARK: - Запросы

struct LoginRequestDTO: Encodable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequestDTO: Encodable, Sendable {
    let name: String
    let email: String
    let password: String
}

struct RefreshRequestDTO: Encodable, Sendable {
    let refreshToken: String
}

// MARK: - Ответы

/// Ответ `/auth/refresh`: только пара токенов.
struct AuthTokensDTO: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    var tokens: AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

/// Ответ `/auth/login` и `/auth/register`: токены + профиль.
struct AuthResponseDTO: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserDTO

    var result: AuthResult {
        AuthResult(
            tokens: AuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
            ),
            user: user
        )
    }
}

struct AuthResult: Sendable {
    let tokens: AuthTokens
    let user: UserDTO
}
