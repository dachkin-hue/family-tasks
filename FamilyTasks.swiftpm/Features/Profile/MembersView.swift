import SwiftUI

/// Состав семьи. Экран простой и без собственной модели:
/// одно чтение без изменений состояния — ViewModel здесь был бы лишним слоем.
struct MembersView: View {

    private let appEnvironment: AppEnvironment

    @State private var state: ViewState<[UserDTO]> = .idle

    @MainActor
    init(appEnvironment: AppEnvironment) {
        self.appEnvironment = appEnvironment
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .loading:
                    LoadingStateView(title: "Загружаем состав семьи…")

                case .failed(let info):
                    ErrorStateView(info: info) {
                        Task { await load() }
                    }

                case .empty:
                    EmptyStateView(
                        title: "Пока никого",
                        message: "Пригласите близких — и задачи станут общими.",
                        systemImage: "person.2"
                    )

                case .loaded(let members):
                    List(members) { member in
                        HStack(spacing: 12) {
                            AvatarView(initials: member.initials, colorHex: member.colorHex, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                    .font(.body)
                                Text(member.email)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(member.role.title)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .organicBackground()
            .navigationTitle("Семья")
            .task {
                if case .idle = state {
                    state = .loading
                    await load()
                }
            }
        }
    }

    private func load() async {
        do {
            let members = try await appEnvironment.memberService.fetchMembers()
            state = members.isEmpty ? .empty : .loaded(members)
        } catch {
            if let apiError = error as? APIError, case .unauthorized = apiError {
                await appEnvironment.session.handleSessionExpired()
                return
            }
            state = .failed(ErrorInfo(error))
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    MembersView(appEnvironment: environment)
        .environment(environment)
}
