import SwiftUI

/// The single screen: field on top, filtered list, editor below. Search is the interface, not a mode.
struct NotebookView: View {
    let model: NotebookModel
    let sync: DropboxSync
    let settings: AppSettings

    @State private var showSettings = false
    @AppStorage("splitRatio") private var splitRatio = 0.4

    private let dividerHeight: CGFloat = 18
    private let minPane: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            header
            statusLine
            split
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .background { shortcuts }
        .sheet(isPresented: $showSettings) {
            SettingsView(sync: sync, settings: settings, onSortChanged: { model.refresh() })
        }
    }

    // MARK: - Regions

    private var header: some View {
        HStack(spacing: 8) {
            SearchField(
                text: model.query,
                shouldFocus: model.pendingFocus == .field,
                onEdit: { model.userTyped($0) },
                onSubmit: { model.submit() },
                onMove: { model.moveSelection(by: $0) },
                onEscape: { model.escape() },
                onFocusHandled: { model.focusHandled() }
            )
            .frame(height: 44)
            .padding(.horizontal, 12)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule, lineWidth: 1))

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// One quiet line under the field: a notice on the left, "offline" on the right. Never an alert.
    private var statusLine: some View {
        HStack(spacing: 8) {
            Text(model.notice ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if sync.isConnected && !sync.isOnline {
                Text("offline")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.secondary)
        .frame(height: 20)
        .padding(.horizontal, 20)
    }

    private var split: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let maxList = max(minPane, total - minPane - dividerHeight)
            let listHeight = min(max(total * splitRatio, minPane), maxList)
            VStack(spacing: 0) {
                list.frame(height: listHeight)
                divider(total: total)
                editor
            }
            .coordinateSpace(name: "split")
        }
    }

    private var list: some View {
        NoteList(
            notes: model.results,
            selectedID: model.selectedID,
            renamingID: model.renamingID,
            onSelect: { model.open($0, focusBody: false) },
            onDelete: { model.delete($0) },
            onBeginRename: { model.beginRename($0) },
            onFinishRename: { model.finishRename($0, to: $1) }
        )
        .overlay(alignment: .bottom) { undoBar }
    }

    @ViewBuilder
    private var undoBar: some View {
        if let undo = model.undo {
            HStack {
                Text("Deleted “\(undo.title)”")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Button("Undo") { model.undoDelete() }
                    .fontWeight(.semibold)
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    private func divider(total: CGFloat) -> some View {
        ZStack {
            Theme.background
            Rectangle().fill(Theme.rule).frame(height: 1)
            Capsule().fill(Theme.secondary.opacity(0.5)).frame(width: 36, height: 3)
        }
        .frame(height: dividerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("split"))
                .onChanged { value in
                    guard total > 0 else { return }
                    splitRatio = min(max(value.location.y / total, 0.15), 0.75)
                }
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var editor: some View {
        if let note = model.selectedNote {
            NoteEditor(
                text: note.body,
                fontSize: settings.fontSize,
                shouldFocus: model.pendingFocus == .body,
                onChange: { model.bodyChanged($0) },
                onEscape: { model.escape() },
                onFocusHandled: { model.focusHandled() }
            )
            .id(note.id)
        } else {
            Theme.field
        }
    }

    // MARK: - Hardware keyboard

    /// Invisible buttons that carry the shortcuts. Optional polish; everything is reachable without them.
    private var shortcuts: some View {
        Group {
            Button("Search") { model.focusField() }.keyboardShortcut("l", modifiers: .command)
            Button("Find") { model.focusField() }.keyboardShortcut("f", modifiers: .command)
            Button("New") { model.newNote() }.keyboardShortcut("n", modifiers: .command)
            Button("Rename") {
                if let id = model.selectedID { model.beginRename(id) }
            }.keyboardShortcut("r", modifiers: .command)
            Button("Delete") {
                if let id = model.selectedID { model.delete(id) }
            }.keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
