import SwiftUI

/// Верхний уровень навигации: сплэш → вход → приложение.
struct RootView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                SplashView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView(appEnvironment: appEnvironment)
            }
        }
        .animation(.default, value: session.state)
        .task {
            await session.restore()
        }
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    RootView()
        .environment(environment)
        .environment(environment.session)
        .modelContainer(environment.modelContainer)
}
