import SwiftUI
import SwiftData

/// Блокнот семьи: записи без сроков, статусов и исполнителей.
/// Порядок — как отдаёт GET /notes: недавно изменённые сверху.
struct NotesView: View {

    /// Редактор открывается листом, а не пушем: он свёрстан как модальный —
    /// со своим NavigationStack и кнопками «Отмена»/«Сохранить».
    /// Обёртка нужна, потому что `.sheet(item:)` требует Identifiable.
    private struct EditTarget: Identifiable {
        let id: UUID
    }

    @State private var model: NotesViewModel
    @State private var isPresentingEditor = false
    @State private var editTarget: EditTarget?
    @State private var quickTitle = ""
    private let appEnvironment: AppEnvironment

    @MainActor
    init(appEnvironment: AppEnvironment) {
        self.appEnvironment = appEnvironment
        _model = State(
            initialValue: NotesViewModel(
                repository: appEnvironment.makeNoteRepository(),
                session: appEnvironment.session
            )
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Заметки")
                .navigationBarTitleDisplayMode(.large)
                .sheet(item: $editTarget) { target in
                    if let note = model.note(withID: target.id) {
                        NoteEditorView(mode: .edit(draft: note.draft), appEnvironment: appEnvironment) { draft in
                            try await model.update(note, draft: draft)
                        }
                    } else {
                        EmptyStateView(
                            title: "Заметка недоступна",
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
                            // Плюс, а не square.and.pencil: на соседней вкладке плюс,
                            // и две разные иконки для одного действия сбивают с толку.
                            Label("Новая заметка", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $isPresentingEditor) {
                    NoteEditorView(mode: .create, appEnvironment: appEnvironment) { draft in
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
            LoadingStateView(title: "Загружаем заметки…")

        case .failed(let info):
            ErrorStateView(info: info) {
                Task { await model.retry() }
            }

        case .empty:
            // Пустое состояние тоже внутри List — иначе перестанет работать pull-to-refresh.
            List {
                Section {
                    emptyView
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    header
                }
            }
            .listStyle(.insetGrouped)
            .organicBackground()
            .searchable(text: $model.searchText, prompt: "Поиск по заметкам")
            .refreshable { await model.refresh() }

        case .loaded(let notes):
            List {
                Section {
                    ForEach(notes) { note in
                        Button {
                            editTarget = EditTarget(id: note.remoteID)
                        } label: {
                            NoteRowView(note: note)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await model.delete(note) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            .tint(Theme.danger)
                        }
                        .organicRow()
                    }
                } header: {
                    header
                } footer: {
                    if model.showsVisibilityFilter && model.hiddenCount > 0 {
                        Text("Заметки «только для родителей» детям не отдаются: \(model.hiddenCount) скрыто.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .organicBackground()
            .searchable(text: $model.searchText, prompt: "Поиск по заметкам")
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

    /// Заголовок секции держит быструю запись и фильтр:
    /// короткая заметка — это часто один заголовок, ради неё не стоит открывать форму.
    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Записать одной строкой", text: $quickTitle)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(quickCreate)

                Button(action: quickCreate) {
                    Label("Добавить", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .imageScale(.large)
                }
                .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.showsVisibilityFilter {
                Picker("Видимость", selection: $model.filter) {
                    ForEach(NoteFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
    }

    @ViewBuilder
    private var emptyView: some View {
        if model.filter == .all && model.searchText.isEmpty {
            EmptyStateView(
                title: "Заметок нет",
                message: "Запишите то, у чего нет срока и исполнителя — список покупок, размеры, телефоны.",
                systemImage: "note.text",
                actionTitle: "Новая заметка",
                action: { isPresentingEditor = true }
            )
        } else {
            EmptyStateView(
                title: model.searchText.isEmpty ? "Здесь пусто" : "Ничего не найдено",
                message: model.searchText.isEmpty
                    ? "В этой видимости заметок пока нет."
                    : "Попробуйте изменить запрос.",
                systemImage: model.searchText.isEmpty ? "note.text" : "magnifyingglass"
            )
        }
    }

    private func quickCreate() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        quickTitle = ""
        Task { await model.quickCreate(title: title) }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    NotesView(appEnvironment: environment)
        .environment(environment)
        .environment(environment.session)
        .modelContainer(environment.modelContainer)
}
