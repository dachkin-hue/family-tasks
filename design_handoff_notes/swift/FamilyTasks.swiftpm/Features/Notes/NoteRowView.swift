import SwiftUI

struct NoteRowView: View {

    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if note.isHiddenFromChildren {
                    Label(Visibility.parents.shortTitle, systemImage: "lock.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !note.body.isEmpty {
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text(metaText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    /// Автор — тот, кто завёл заметку, а дата — последней правки:
    /// общую заметку может дополнить любой член семьи.
    private var metaText: String {
        let author = note.authorName ?? "Неизвестный автор"
        return "\(author) · изменено \(note.updatedAt.formatted(.relative(presentation: .named)))"
    }
}

#Preview {
    List {
        NoteRowView(note: NoteItem(dto: NoteDTO(
            id: UUID(),
            title: "Что купить в «Метро»",
            body: "Крупы, кофе в зёрнах, стиральный порошок.",
            visibility: .family,
            authorId: UserDTO.previewPartner.id,
            authorName: UserDTO.previewPartner.name,
            createdAt: Date(),
            updatedAt: Date()
        )))
    }
}
