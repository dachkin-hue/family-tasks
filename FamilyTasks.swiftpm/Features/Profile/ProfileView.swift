import SwiftUI

struct ProfileView: View {

    @Environment(AppSession.self) private var session
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let user = session.currentUser {
                    Section {
                        HStack(spacing: 16) {
                            AvatarView(initials: user.initials, colorHex: user.colorHex, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(Theme.heading(20, relativeTo: .title3))
                                    .foregroundStyle(Theme.text)
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(user.role.title)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section("Подключение") {
                    LabeledContent("Режим") {
                        Text(AppConfig.useMockBackend ? "Локальные данные" : "Сервер")
                    }
                    if !AppConfig.useMockBackend {
                        LabeledContent("Адрес") {
                            Text(AppConfig.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingSignOut = true
                    } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .organicBackground()
            .navigationTitle("Профиль")
            .confirmationDialog(
                "Выйти из аккаунта?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Выйти", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    ProfileView()
        .environment(environment.session)
}
