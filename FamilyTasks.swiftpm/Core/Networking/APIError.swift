import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case offline
    case cancelled
    case unauthorized
    case forbidden
    case notFound
    case validation(message: String)
    /// Сервер попросил притормозить: перебор пароля или частые регистрации.
    case tooManyRequests(message: String?, retryAfter: Int?)
    case server(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес запроса."
        case .offline:
            return "Нет подключения к интернету."
        case .cancelled:
            return "Запрос отменён."
        case .unauthorized:
            return "Сессия истекла. Войдите заново."
        case .forbidden:
            return "Недостаточно прав для этого действия."
        case .notFound:
            return "Данные не найдены. Возможно, их уже удалили."
        case .validation(let message):
            return message
        case .tooManyRequests(let message, let retryAfter):
            // Текст сервера уже человеческий и содержит срок — берём его.
            // Свой вариант нужен, только если сервер ответил без detail.
            if let message { return message }
            guard let retryAfter else {
                return "Слишком много попыток. Повторите позже."
            }
            return "Слишком много попыток. Повторите через \(Self.humanDelay(retryAfter))."
        case .server(let status, let message):
            return message ?? "Ошибка сервера (\(status)). Попробуйте позже."
        case .decoding:
            return "Сервер вернул данные в неожиданном формате."
        case .transport(let description):
            return description
        }
    }

    /// Имеет ли смысл показывать кнопку «Повторить».
    var isRetryable: Bool {
        switch self {
        case .offline, .transport, .cancelled:
            return true
        case .server(let status, _):
            return status >= 500
        default:
            // Для .tooManyRequests — намеренно false: кнопка «Повторить»
            // предлагала бы ровно то действие, которое сейчас заблокировано.
            return false
        }
    }

    /// Через сколько можно повторить, в секундах. Нужен экрану входа для отсчёта.
    var retryAfter: Int? {
        if case .tooManyRequests(_, let retryAfter) = self { return retryAfter }
        return nil
    }

    private static func humanDelay(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = Int((Double(seconds) / 60).rounded(.up))
            return "\(minutes) мин"
        }
        return "\(seconds) с"
    }
}
