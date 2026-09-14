import SwiftUI

/// Главный экран после входа. Каждая вкладка держит свой NavigationStack —
/// так состояние навигации не теряется при переключении.
/// Синтаксис `.tabItem` выбран намеренно: работает и на iOS 17, и на iOS 18+.
struct MainTabView: View {

    private let appEnvironment: AppEnvironment

    @MainActor
    init(appEnvironment: AppEnvironment) {
        self.appEnvironment = appEnvironment
    }

    var body: some View {
        TabView {
            TaskListView(appEnvironment: appEnvironment)
                .tabItem {
                    Label("Задачи", systemImage: "checklist")
                }

            NotesView(appEnvironment: appEnvironment)
                .tabItem {
                    Label("Заметки", systemImage: "note.text")
                }

            MembersView(appEnvironment: appEnvironment)
                .tabItem {
                    Label("Семья", systemImage: "person.2")
                }

            ProfileView()
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle")
                }
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    MainTabView(appEnvironment: environment)
        .environment(environment)
        .environment(environment.session)
        .modelContainer(environment.modelContainer)
}
