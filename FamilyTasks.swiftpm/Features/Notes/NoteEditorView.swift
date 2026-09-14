import SwiftUI

/// Создание и редактирование заметки. Одна форма на оба сценария,
/// как у задач: различаются заголовок, начальные значения и обработчик сохранения.
struct NoteEditorView: View {

    enum Mode {
        case create
        case edit(draft: NoteDraft)

        var title: String {
            switch self {
            case .create: return "Новая заметка"
            case .edit: return "Заметка"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private let appEnvironment: AppEnvironment
    private let onSave: (NoteDraft) async throws -> Void

    @State private var title: String
    @State private var body_: String
    @State private var visibility: Visibility
    @State private var isSaving = false
    @State private var errorInfo: ErrorInfo?

    private let modeTitle: String

    @MainActor
    init(
        mode: Mode,
        appEnvironment: AppEnvironment,
        onSave: @escaping (NoteDraft) async throws -> Void
    ) {
        self.appEnvironment = appEnvironment
        self.onSave = onSave
        self.modeTitle = mode.title

        switch mode {
        case .create:
            _title = State(initialValue: "")
            _body_ = State(initialValue: "")
            _visibility = State(initialValue: .family)

        case .edit(let draft):
            _title = State(initialValue: draft.title)
            _body_ = State(initialValue: draft.body ?? "")
            _visibility = State(initialValue: draft.visibility)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Заголовок", text: $title, axis: .vertical)
                        .lineLimit(1...3)

                    TextField("Текст — можно оставить пустым", text: $body_, axis: .vertical)
                        .lineLimit(4...12)
                }

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
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var visibilityHint: String {
        switch visibility {
        case .family:
            return "Общую заметку может дополнить любой член семьи; автор остаётся прежним."
        case .parents:
            return "Дети не увидят её в списке и не смогут открыть напрямую."
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard isValid, !isSaving else { return }
        let trimmedBody = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = NoteDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: trimmedBody.isEmpty ? nil : trimmedBody,
            visibility: visibility
        )

        isSaving = true
        errorInfo = nil

        Task {
            do {
                try await onSave(draft)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorInfo = ErrorInfo(error)
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    NoteEditorView(mode: .create, appEnvironment: environment) { _ in }
        .environment(environment)
}
