import SwiftUI

/// Создание и редактирование задачи. Одна форма на оба сценария —
/// различается только заголовок, начальные значения и обработчик сохранения.
struct TaskEditorView: View {

    enum Mode {
        case create
        case edit(draft: TaskDraft, status: TaskStatus)

        var title: String {
            switch self {
            case .create: return "Новая задача"
            case .edit: return "Изменить задачу"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private let appEnvironment: AppEnvironment
    private let onSave: (TaskDraft, TaskStatus) async throws -> Void

    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: TaskPriority
    @State private var status: TaskStatus
    @State private var assigneeID: UUID?
    @State private var visibility: Visibility

    @State private var members: [UserDTO] = []
    @State private var isSaving = false
    @State private var errorInfo: ErrorInfo?

    private let isEditing: Bool
    private let modeTitle: String

    @MainActor
    init(
        mode: Mode,
        appEnvironment: AppEnvironment,
        onSave: @escaping (TaskDraft, TaskStatus) async throws -> Void
    ) {
        self.appEnvironment = appEnvironment
        self.onSave = onSave
        self.modeTitle = mode.title

        switch mode {
        case .create:
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: Self.defaultDueDate())
            _priority = State(initialValue: .medium)
            _status = State(initialValue: .todo)
            _assigneeID = State(initialValue: appEnvironment.session.currentUser?.id)
            _visibility = State(initialValue: .family)
            self.isEditing = false

        case .edit(let draft, let currentStatus):
            _title = State(initialValue: draft.title)
            _notes = State(initialValue: draft.notes ?? "")
            _hasDueDate = State(initialValue: draft.dueDate != nil)
            _dueDate = State(initialValue: draft.dueDate ?? Self.defaultDueDate())
            _priority = State(initialValue: draft.priority)
            _status = State(initialValue: currentStatus)
            _assigneeID = State(initialValue: draft.assigneeId)
            _visibility = State(initialValue: draft.visibility)
            self.isEditing = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что нужно сделать", text: $title, axis: .vertical)
                        .lineLimit(1...3)

                    TextField("Заметки", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Срок") {
                    Toggle("Указать срок", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Когда", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Кто делает") {
                    Picker("Исполнитель", selection: $assigneeID) {
                        Text("Не назначен").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.name).tag(UUID?.some(member.id))
                        }
                    }
                }

                Section("Важность") {
                    Picker("Важность", selection: $priority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Label(priority.title, systemImage: priority.systemImage).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if isParent {
                    Section {
                        Picker("Кому видна", selection: $visibility) {
                            ForEach(Visibility.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Кому видна")
                    } footer: {
                        Text(visibilityHint)
                    }
                }

                if isEditing {
                    Section("Статус") {
                        Picker("Статус", selection: $status) {
                            ForEach(TaskStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                    }
                }

                if let errorInfo {
                    Section {
                        Text(errorInfo.message)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .organicBackground()
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Сохранить", action: save)
                            .disabled(!isValid)
                    }
                }
            }
            .task {
                members = (try? await appEnvironment.memberService.fetchMembers()) ?? []
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// Переключатель видят только родители: ребёнку сервер вернёт 403,
    /// а скрытые задачи ему и так не приходят — выбирать нечего.
    private var isParent: Bool {
        appEnvironment.session.currentUser?.role == .parent
    }

    private var visibilityHint: String {
        guard visibility == .parents else {
            return "Задачу увидят все члены семьи."
        }
        if assigneeIsChild {
            return "Скрытую задачу нельзя назначить ребёнку — он её не увидит."
        }
        return "Дети не увидят её в списке и не смогут открыть напрямую."
    }

    /// Тот же запрет, что и на сервере: иначе задача висела бы
    /// на человеке, которому её не показывают.
    private var assigneeIsChild: Bool {
        guard let assigneeID else { return false }
        return members.first { $0.id == assigneeID }?.role == .child
    }

    private var isValid: Bool {
        if visibility == .parents && assigneeIsChild { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard isValid, !isSaving else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority,
            assigneeId: assigneeID,
            visibility: visibility
        )

        isSaving = true
        errorInfo = nil

        Task {
            do {
                try await onSave(draft, status)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorInfo = ErrorInfo(error)
            }
        }
    }

    private static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
        return today > Date() ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    TaskEditorView(mode: .create, appEnvironment: environment) { _, _ in }
        .environment(environment)
}
