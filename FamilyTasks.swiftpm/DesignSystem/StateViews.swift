import SwiftUI

/// Заглушка загрузки. Используется только при холодном старте,
/// когда показать из кэша ещё нечего.
struct LoadingStateView: View {
    var title: String = "Загружаем…"

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text(title)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorStateView: View {
    let info: ErrorInfo
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(info.title).font(Theme.heading(21, relativeTo: .title3))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.accent)
            }
        } description: {
            Text(info.message)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            if let retry, info.isRetryable {
                Button("Повторить", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .font(Theme.body(16, weight: .semibold))
            }
        }
        .background(Theme.background)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).font(Theme.heading(21, relativeTo: .title3))
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.textTertiary)
            }
        } description: {
            Text(message)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .font(Theme.body(16, weight: .semibold))
            }
        }
        .background(Theme.background)
    }
}

#Preview("Загрузка") {
    LoadingStateView()
}

#Preview("Ошибка") {
    ErrorStateView(
        info: ErrorInfo(APIError.offline),
        retry: {}
    )
}

#Preview("Пусто") {
    EmptyStateView(
        title: "Задач нет",
        message: "Добавьте первую задачу — она появится у всех членов семьи.",
        systemImage: "checkmark.circle",
        actionTitle: "Новая задача",
        action: {}
    )
}
