import SwiftUI

/// Titles with a relative modified time. No icons, no chevrons, no iOS-blue selection.
struct NoteList: View {
    let notes: [Note]
    let selectedID: String?
    let renamingID: String?
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onBeginRename: (String) -> Void
    let onFinishRename: (String, String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(notes) { note in
                    NoteRow(
                        note: note,
                        isSelected: note.id == selectedID,
                        isRenaming: note.id == renamingID,
                        onFinishRename: { onFinishRename(note.id, $0) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(note.id) }
                    .listRowBackground(note.id == selectedID ? Theme.selection : Color.clear)
                    .listRowSeparatorTint(Theme.rule)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { onDelete(note.id) } label: { Text("Delete") }
                    }
                    .contextMenu {
                        Button("Rename") { onBeginRename(note.id) }
                        Button("Delete", role: .destructive) { onDelete(note.id) }
                    }
                    .id(note.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.never)
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.none) { proxy.scrollTo(id) }
            }
        }
        .overlay {
            if notes.isEmpty {
                Text("Type a title, then Return.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondary)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let isRenaming: Bool
    let onFinishRename: (String) -> Void

    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isRenaming {
                TextField("Title", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .focused($editing)
                    .submitLabel(.done)
                    .onSubmit { onFinishRename(draft) }
                    .onAppear {
                        draft = note.title
                        editing = true
                    }
                    .onChange(of: editing) { _, isEditing in
                        if !isEditing { onFinishRename(draft) }
                    }
            } else {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(RelativeTime.string(for: note.modified))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .frame(minHeight: 40)
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .numeric
        return f
    }()

    static func string(for date: Date, now: Date = Date()) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return "now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
