import SwiftUI

/// Главный экран после входа. Каждая вкладка держит свой NavigationStack —
/// так состояние навигации не теряется при переключении.
/// Синтаксис `.tabItem` выбран намеренно: работает и на iOS 17, и на iOS 18+.
struct MainTabView: View {

    enum Tab: Hashable {
        case tasks
        case notes
        case family
        case profile
    }

    private let appEnvironment: AppEnvironment
    @State private var selection: Tab

    @MainActor
    init(appEnvironment: AppEnvironment) {
        self.appEnvironment = appEnvironment
        // Обычно открываются «Задачи». Аргумент запуска нужен CI,
        // чтобы снять скриншот сразу нужной вкладки.
        _selection = State(initialValue: LaunchScreen.requested?.tab ?? .tasks)
    }

    var body: some View {
        TabView(selection: $selection) {
            TaskListView(appEnvironment: appEnvironment)
                .tag(Tab.tasks)
                .tabItem {
                    Label("Задачи", systemImage: "checklist")
                }

            NotesView(appEnvironment: appEnvironment)
                .tag(Tab.notes)
                .tabItem {
                    Label("Заметки", systemImage: "note.text")
                }

            MembersView(appEnvironment: appEnvironment)
                .tag(Tab.family)
                .tabItem {
                    Label("Семья", systemImage: "person.2")
                }

            ProfileView()
                .tag(Tab.profile)
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
