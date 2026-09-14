import Foundation

protocol APIClient: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint) async throws -> T
    func sendIgnoringResponse(_ endpoint: APIEndpoint) async throws
}

/// Ответ для эндпоинтов, которые возвращают 204 No Content.
struct EmptyResponse: Codable, Sendable {}

/// Единственная точка выхода в сеть.
/// `actor` — потому что внутри есть мутируемое состояние: задача обновления токена,
/// которую нельзя запускать параллельно из нескольких экранов.
actor NetworkManager: APIClient {

    private let baseURL: URL
    private let tokenStorage: TokenStorage
    private let session: URLSession
    private var refreshTask: Task<AuthTokens, Error>?

    init(baseURL: URL, tokenStorage: TokenStorage, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStorage = tokenStorage
        self.session = session
    }

    // MARK: - Публичный API

    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await perform(endpoint)
        if let empty = EmptyResponse() as? T {
            return empty
        }
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(T.self): \(error)")
        }
    }

    func sendIgnoringResponse(_ endpoint: APIEndpoint) async throws {
        _ = try await perform(endpoint)
    }

    // MARK: - Выполнение запроса

    private func perform(_ endpoint: APIEndpoint, isRetry: Bool = false) async throws -> Data {
        let request = try await makeRequest(endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw APIError.cancelled
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError.offline
            case .timedOut:
                throw APIError.transport("Сервер не ответил вовремя.")
            default:
                throw APIError.transport(error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Некорректный ответ сервера.")
        }

        switch http.statusCode {
        case 200..<300:
            return data

        case 401 where endpoint.requiresAuth && !isRetry:
            _ = try await refreshTokens()
            return try await perform(endpoint, isRetry: true)

        case 401:
            await tokenStorage.clear()
            throw APIError.unauthorized

        case 403:
            throw APIError.forbidden

        case 404:
            throw APIError.notFound

        case 400, 409, 422:
            throw APIError.validation(message: Self.serverMessage(from: data) ?? "Проверьте введённые данные.")

        case 429:
            throw APIError.tooManyRequests(
                message: Self.serverMessage(from: data),
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            )

        default:
            throw APIError.server(status: http.statusCode, message: Self.serverMessage(from: data))
        }
    }

    private func makeRequest(_ endpoint: APIEndpoint) async throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appending(path: endpoint.path),
            resolvingAgainstBaseURL: false
        )
        if !endpoint.query.isEmpty {
            components?.queryItems = endpoint.query
        }
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = AppConfig.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if endpoint.requiresAuth {
            guard var tokens = await tokenStorage.current() else { throw APIError.unauthorized }
            if tokens.isExpired {
                tokens = try await refreshTokens()
            }
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Обновление токена

    /// Несколько параллельных 401 приводят к одному запросу на refresh.
    private func refreshTokens() async throws -> AuthTokens {
        if let refreshTask {
            return try await refreshTask.value
        }

        guard let current = await tokenStorage.current() else {
            throw APIError.unauthorized
        }

        let task = Task<AuthTokens, Error> { [baseURL, session] in
            let endpoint = try APIEndpoint.refresh(refreshToken: current.refreshToken)
            var request = URLRequest(url: baseURL.appending(path: endpoint.path))
            request.httpMethod = endpoint.method.rawValue
            request.httpBody = endpoint.body
            request.timeoutInterval = AppConfig.requestTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.unauthorized
            }
            let dto = try JSONCoding.decoder.decode(AuthTokensDTO.self, from: data)
            return dto.tokens
        }

        refreshTask = task
        defer { refreshTask = nil }

        do {
            let tokens = try await task.value
            await tokenStorage.save(tokens)
            return tokens
        } catch {
            await tokenStorage.clear()
            throw APIError.unauthorized
        }
    }

    // MARK: - Разбор ошибки бэкенда

    /// FastAPI отдаёт `{"detail": "..."}` либо `{"detail": [{"msg": "..."}]}`.
    private static func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let detail = object["detail"] as? String { return detail }
        if let list = object["detail"] as? [[String: Any]] {
            let messages = list.compactMap { $0["msg"] as? String }
            if !messages.isEmpty { return messages.joined(separator: "\n") }
        }
        if let message = object["message"] as? String { return message }
        return nil
    }
}
