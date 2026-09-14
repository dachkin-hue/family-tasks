import Foundation
import Security

struct AuthTokens: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// Обновляем заранее, чтобы не ловить 401 ровно на границе срока жизни.
    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

/// Хранилище токенов в Keychain. `actor` — доступ идёт и из сетевого слоя, и из сессии.
actor TokenStorage {

    private let service: String
    private let account = "auth.tokens"
    private var cached: AuthTokens?
    private var didLoad = false

    init(service: String) {
        self.service = service
    }

    func current() -> AuthTokens? {
        if !didLoad {
            didLoad = true
            if let data = Keychain.read(service: service, account: account) {
                cached = try? JSONDecoder().decode(AuthTokens.self, from: data)
            }
        }
        return cached
    }

    func save(_ tokens: AuthTokens) {
        cached = tokens
        didLoad = true
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        Keychain.save(data, service: service, account: account)
    }

    func clear() {
        cached = nil
        didLoad = true
        Keychain.delete(service: service, account: account)
    }
}

/// Минимальная обёртка над Security.framework — сторонние зависимости не нужны.
enum Keychain {

    static func save(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
