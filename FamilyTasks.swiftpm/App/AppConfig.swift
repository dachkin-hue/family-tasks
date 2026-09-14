import Foundation

/// Единая точка конфигурации сборки.
enum AppConfig {

    /// Бэкенда пока нет — приложение работает на встроенном моке.
    /// После деплоя FastAPI на VPS: поставьте `false` и укажите реальный `baseURL`.
    static let useMockBackend = true

    /// Базовый адрес REST API. Должен быть HTTPS, иначе потребуется исключение в ATS.
    static let baseURL = URL(string: "https://api.example.com/v1")!

    /// Идентификатор сервиса в Keychain (обычно совпадает с bundle id).
    static let keychainService = "com.yourcompany.familytasks"

    /// Таймаут одного сетевого запроса.
    static let requestTimeout: TimeInterval = 30
}
