import SwiftUI

// Визуальные атрибуты доменных типов держим отдельно от моделей:
// модели остаются чистыми и не тянут за собой SwiftUI.

extension TaskPriority {
    /// Акцент системы — только для того, что требует внимания.
    /// Обычная важность нейтральна, иначе «срочно» перестанет выделяться.
    var tint: Color {
        switch self {
        case .low: return Theme.textTertiary
        case .medium: return Theme.textSecondary
        case .high: return Theme.accent
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .medium: return "minus.circle"
        case .high: return "exclamationmark.circle"
        }
    }
}

extension TaskStatus {
    /// Второй акцент системы отвечает за движение и завершённость.
    var tint: Color {
        switch self {
        case .todo: return Theme.textTertiary
        case .inProgress: return Theme.accent2
        case .done: return Theme.accent2Strong
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }
}

extension Color {
    /// Цвет из строки вида "#RRGGBB". При некорректном значении — акцент системы.
    init(hex: String?) {
        guard let hex else { self = Color(hex: "#c67139"); return }
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            self = Color(red: 0.776, green: 0.443, blue: 0.224)
            return
        }
        self = Color(
            red: Double((number & 0xFF0000) >> 16) / 255,
            green: Double((number & 0x00FF00) >> 8) / 255,
            blue: Double(number & 0x0000FF) / 255
        )
    }
}

/// Кружок с инициалами исполнителя.
struct AvatarView: View {
    let initials: String
    var colorHex: String?
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex).gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

extension Date {
    /// «Сегодня, 18:00», «Завтра», «12 окт» — короткая подпись для срока.
    var dueLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Сегодня, " + formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInTomorrow(self) {
            return "Завтра, " + formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(self) {
            return "Вчера"
        }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}
