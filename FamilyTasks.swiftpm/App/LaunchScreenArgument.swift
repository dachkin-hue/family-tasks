import Foundation

/// Экран, с которого приложение должно открыться при запуске.
///
/// Нужен только для съёмки скриншотов в CI: симулятором без UI-тестов
/// нельзя «потыкать», зато можно запустить приложение несколько раз
/// с разными аргументами и снять по кадру с каждого.
///
/// ```
/// xcrun simctl launch <udid> <bundle-id> -screen notes
/// ```
///
/// В обычном запуске аргумента нет, и всё работает как всегда:
/// сплэш, затем вход или список задач.
enum LaunchScreen: String {
    case login
    case tasks
    case notes
    case family
    case profile

    /// Значение из аргументов запуска, если оно там есть и распознано.
    static var requested: LaunchScreen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screen"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return LaunchScreen(rawValue: arguments[index + 1])
    }

    /// На каких экранах нужен вход. Для `login` — наоборот, сессию надо сбросить.
    var requiresSignedInUser: Bool { self != .login }

    /// Вкладка, которую надо открыть.
    var tab: MainTabView.Tab? {
        switch self {
        case .login: return nil
        case .tasks: return .tasks
        case .notes: return .notes
        case .family: return .family
        case .profile: return .profile
        }
    }
}
