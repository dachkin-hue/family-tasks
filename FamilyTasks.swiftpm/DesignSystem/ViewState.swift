import Foundation

/// Человекочитаемое представление ошибки для UI.
struct ErrorInfo: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isRetryable: Bool

    init(title: String, message: String, isRetryable: Bool) {
        self.title = title
        self.message = message
        self.isRetryable = isRetryable
    }

    init(_ error: Error) {
        if let apiError = error as? APIError {
            self.title = ErrorInfo.title(for: apiError)
            self.message = apiError.errorDescription ?? "Неизвестная ошибка."
            self.isRetryable = apiError.isRetryable
        } else {
            self.title = "Что-то пошло не так"
            self.message = error.localizedDescription
            self.isRetryable = true
        }
    }

    private static func title(for error: APIError) -> String {
        switch error {
        case .offline: return "Нет связи"
        case .unauthorized: return "Сессия истекла"
        case .forbidden: return "Нет доступа"
        case .notFound: return "Не найдено"
        case .validation: return "Проверьте данные"
        case .tooManyRequests: return "Слишком много попыток"
        default: return "Что-то пошло не так"
        }
    }

    static func == (lhs: ErrorInfo, rhs: ErrorInfo) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message && lhs.isRetryable == rhs.isRetryable
    }
}

/// Состояние экрана, загружающего данные.
/// `empty` вынесено отдельно от `loaded([])` — у пустого списка своя вёрстка и свой призыв к действию.
enum ViewState<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(ErrorInfo)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
