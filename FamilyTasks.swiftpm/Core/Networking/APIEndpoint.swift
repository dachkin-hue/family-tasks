import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Описание одного эндпоинта.
/// Вся карта REST API собрана в расширении ниже — при изменениях на бэкенде правится только этот файл.
struct APIEndpoint: Sendable {
    var path: String
    var method: HTTPMethod = .get
    var query: [URLQueryItem] = []
    var body: Data?
    var requiresAuth: Bool = true
}

extension APIEndpoint {

    // MARK: - Auth

    static func login(email: String, password: String) throws -> APIEndpoint {
        APIEndpoint(
            path: "auth/login",
            method: .post,
            body: try JSONCoding.encode(LoginRequestDTO(email: email, password: password)),
            requiresAuth: false
        )
    }

    static func register(name: String, email: String, password: String) throws -> APIEndpoint {
        APIEndpoint(
            path: "auth/register",
            method: .post,
            body: try JSONCoding.encode(RegisterRequestDTO(name: name, email: email, password: password)),
            requiresAuth: false
        )
    }

    static func refresh(refreshToken: String) throws -> APIEndpoint {
        APIEndpoint(
            path: "auth/refresh",
            method: .post,
            body: try JSONCoding.encode(RefreshRequestDTO(refreshToken: refreshToken)),
            requiresAuth: false
        )
    }

    static var me: APIEndpoint {
        APIEndpoint(path: "me")
    }

    static var logout: APIEndpoint {
        APIEndpoint(path: "auth/logout", method: .post)
    }

    // MARK: - Family

    static var members: APIEndpoint {
        APIEndpoint(path: "family/members")
    }

    // MARK: - Tasks

    static var tasks: APIEndpoint {
        APIEndpoint(path: "tasks")
    }

    static func createTask(_ draft: TaskDraft) throws -> APIEndpoint {
        APIEndpoint(path: "tasks", method: .post, body: try JSONCoding.encode(draft))
    }

    static func updateTask(id: UUID, payload: TaskUpdateDTO) throws -> APIEndpoint {
        APIEndpoint(path: "tasks/\(id.uuidString)", method: .put, body: try JSONCoding.encode(payload))
    }

    static func deleteTask(id: UUID) -> APIEndpoint {
        APIEndpoint(path: "tasks/\(id.uuidString)", method: .delete)
    }
}
