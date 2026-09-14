import SwiftUI
import SwiftData

@main
struct FamilyTasksApp: App {

    @State private var appEnvironment = AppEnvironment.live()

    init() {
        // Навбар и таб-бар не красятся модификаторами SwiftUI — только appearance.
        Theme.applySystemAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .environment(appEnvironment.session)
                .modelContainer(appEnvironment.modelContainer)
                // Акцент системы для всех кнопок, переключателей и полей.
                .tint(Theme.accent)
                .background(Theme.background)
        }
    }
}
