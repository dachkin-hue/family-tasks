import SwiftUI

struct TaskDetailView: View {

    let task: TaskItem
    let model: TaskListViewModel
    let appEnvironment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEditor = false
    @State private var isConfirmingDelete = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(Theme.heading(23, relativeTo: .title2))
                        .foregroundStyle(Theme.text)
                        .strikethrough(task.isCompleted, color: Theme.textTertiary)

                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Детали") {
                LabeledContent("Статус") {
                    Label(task.status.title, systemImage: task.status.systemImage)
                        .foregroundStyle(task.status.tint)
                }

                LabeledContent("Важность") {
                    Label(task.priority.title, systemImage: task.priority.systemImage)
                        .foregroundStyle(task.priority.tint)
                }

                if let dueDate = task.dueDate {
                    LabeledContent("Срок") {
                        Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(task.isOverdue ? .red : .primary)
                    }
                }

                LabeledContent("Кому видна") {
                    Label(task.visibility.title, systemImage: task.isHiddenFromChildren ? "lock.fill" : "person.2")
                        .foregroundStyle(task.isHiddenFromChildren ? Theme.accent : Theme.textSecondary)
                }

                LabeledContent("Исполнитель") {
                    Text(task.assigneeName ?? "Не назначен")
                        .foregroundStyle(task.assigneeName == nil ? .secondary : .primary)
                }

                LabeledContent("Обновлено") {
                    Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Section {
                Button {
                    Task { await model.toggleCompletion(task) }
                } label: {
                    Label(
                        task.isCompleted ? "Вернуть в работу" : "Отметить выполненной",
                        systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Удалить задачу", systemImage: "trash")
                }
            }
        }
        .organicBackground()
        .navigationTitle("Задача")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Изменить") { isPresentingEditor = true }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            TaskEditorView(
                mode: .edit(draft: task.draft, status: task.status),
                appEnvironment: appEnvironment
            ) { draft, status in
                try await model.update(task, draft: draft, status: status)
            }
        }
        .confirmationDialog(
            "Удалить задачу?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task {
                    await model.delete(task)
                    dismiss()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Задача исчезнет у всех членов семьи.")
        }
    }
}
