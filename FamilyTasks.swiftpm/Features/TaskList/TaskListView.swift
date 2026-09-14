import SwiftUI
import SwiftData

struct TaskListView: View {

    @State private var model: TaskListViewModel
    @State private var isPresentingEditor = false
    private let appEnvironment: AppEnvironment

    @MainActor
    init(appEnvironment: AppEnvironment) {
        self.appEnvironment = appEnvironment
        _model = State(
            initialValue: TaskListViewModel(
                repository: appEnvironment.makeTaskRepository(),
                session: appEnvironment.session
            )
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Задачи")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: UUID.self) { id in
                    if let task = model.task(withID: id) {
                        TaskDetailView(task: task, model: model, appEnvironment: appEnvironment)
                    } else {
                        EmptyStateView(
                            title: "Задача недоступна",
                            message: "Возможно, её удалили с другого устройства.",
                            systemImage: "questionmark.folder"
                        )
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingEditor = true
                        } label: {
                            Label("Новая задача", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $isPresentingEditor) {
                    TaskEditorView(mode: .create, appEnvironment: appEnvironment) { draft, _ in
                        try await model.create(draft)
                    }
                }
                .alert(
                    model.operationError?.title ?? "Ошибка",
                    isPresented: Binding(
                        get: { model.operationError != nil },
                        set: { isPresented in
                            if !isPresented { model.operationError = nil }
                        }
                    ),
                    presenting: model.operationError
                ) { _ in
                    Button("Понятно", role: .cancel) {}
                } message: { info in
                    Text(info.message)
                }
                .task {
                    await model.onAppear()
                }
        }
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            LoadingStateView(title: "Загружаем задачи…")

        case .failed(let info):
            ErrorStateView(info: info) {
                Task { await model.retry() }
            }

        case .empty:
            // Пустое состояние тоже живёт в List — иначе перестанет работать pull-to-refresh.
            List {
                Section {
                    emptyView
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    filterPicker
                        .textCase(nil)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .organicBackground()
            .searchable(text: $model.searchText, prompt: "Поиск по задачам")
            .refreshable { await model.refresh() }

        case .loaded(let tasks):
            List {
                Section {
                    ForEach(tasks) { task in
                        NavigationLink(value: task.remoteID) {
                            TaskRowView(task: task) {
                                Task { await model.toggleCompletion(task) }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await model.delete(task) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Task { await model.advanceStatus(task) }
                            } label: {
                                Label("Статус", systemImage: "arrow.forward.circle")
                            }
                            .tint(Theme.accent2)
                        }
                        .organicRow()
                    }
                } header: {
                    filterPicker
                        .textCase(nil)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .organicBackground()
            .searchable(text: $model.searchText, prompt: "Поиск по задачам")
            .refreshable { await model.refresh() }
            .overlay(alignment: .top) {
                if model.isRefreshing {
                    ProgressView()
                        .padding(6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 4)
                }
            }
        }
    }

    /// Кнопка «Новая задача» уместна только в общем списке:
    /// в «Моих» или «Готово» она уводила бы не туда, куда ждёт пользователь.
    @ViewBuilder
    private var emptyView: some View {
        if model.filter == .all && model.searchText.isEmpty {
            EmptyStateView(
                title: emptyTitle,
                message: emptyMessage,
                systemImage: "tray",
                actionTitle: "Новая задача",
                action: { isPresentingEditor = true }
            )
        } else {
            EmptyStateView(
                title: emptyTitle,
                message: emptyMessage,
                systemImage: model.filter == .done ? "checkmark.circle" : "magnifyingglass"
            )
        }
    }

    private var filterPicker: some View {
        Picker("Фильтр", selection: $model.filter) {
            ForEach(TaskFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
    }

    private var emptyTitle: String {
        model.searchText.isEmpty ? "Задач нет" : "Ничего не найдено"
    }

    private var emptyMessage: String {
        if !model.searchText.isEmpty {
            return "Попробуйте изменить запрос."
        }
        switch model.filter {
        case .all: return "Добавьте первую задачу — её увидят все члены семьи."
        case .mine: return "На вас пока ничего не назначено."
        case .today: return "На сегодня дел не запланировано."
        case .done: return "Выполненных задач пока нет."
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    TaskListView(appEnvironment: environment)
        .environment(environment)
        .environment(environment.session)
        .modelContainer(environment.modelContainer)
}
