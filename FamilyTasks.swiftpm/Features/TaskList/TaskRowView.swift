import SwiftUI

struct TaskRowView: View {

    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.status.systemImage)
                    .font(.title2)
                    .foregroundStyle(task.status.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Отметить невыполненной" : "Отметить выполненной")

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(Theme.body(16))
                    .strikethrough(task.isCompleted, color: Theme.textTertiary)
                    .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.text)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.dueLabel, systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textSecondary)
                    }

                    if task.priority != .medium {
                        Label(task.priority.title, systemImage: task.priority.systemImage)
                            .foregroundStyle(task.priority.tint)
                    }

                    if task.status == .inProgress {
                        Label(task.status.title, systemImage: task.status.systemImage)
                            .foregroundStyle(task.status.tint)
                    }
                }
                .font(Theme.body(12, relativeTo: .caption))
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)

            if let assigneeName = task.assigneeName {
                AvatarView(initials: Self.initials(from: assigneeName), colorHex: nil, size: 30)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}
