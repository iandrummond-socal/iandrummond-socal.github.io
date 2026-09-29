import Foundation
import Observation

/// The whole interaction model in one place: one field that searches and creates, a filtered list, one open note.
@MainActor
@Observable
final class NotebookModel {
    enum Focus { case field, body }

    struct UndoInfo: Identifiable {
        let id = UUID()
        let title: String
        let record: NoteStore.TrashRecord
    }

    /// Text shown in the field. Views only write it through `userTyped`.
    private(set) var query = ""
    private(set) var results: [Note] = []
    private(set) var selectedID: String?
    /// True once the user picked the row (arrows / tap); false when it was only auto-highlighted by a title prefix.
    private(set) var selectionIsExplicit = false
    /// Which control should take keyboard focus next; the view clears it once it has.
    private(set) var pendingFocus: Focus? = .field
    private(set) var notice: String?
    private(set) var undo: UndoInfo?
    private(set) var renamingID: String?
    /// Bumped whenever the list is rebuilt, so views re-read notes changed behind the model's back (sync).
    private(set) var tick = 0

    let settings: AppSettings
    @ObservationIgnored private let store: NoteStore
    /// The query the list is filtered by. Differs from `query` while the field is echoing a selected title.
    @ObservationIgnored private var listQuery = ""
    @ObservationIgnored private var restoreQuery = ""
    @ObservationIgnored private var echoing = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    /// Ask the sync layer to run soon (seconds of debounce).
    @ObservationIgnored var onLocalChange: ((TimeInterval) -> Void)?

    init(store: NoteStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        refresh()
    }

    var selectedNote: Note? { selectedID.flatMap { store.note(forID: $0) } }

    // MARK: - Field

    /// Called only for edits the user made in the field.
    func userTyped(_ text: String) {
        if echoing {
            echoing = false
            if text.isEmpty {
                // Clearing a selected title brings back the query that was there before.
                query = restoreQuery
                listQuery = restoreQuery
                refresh()
                return
            }
        }
        flushSave()
        query = text
        listQuery = text
        refresh()
        autoSelect()
    }

    /// Return in the field.
    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectionIsExplicit, let id = selectedID, store.note(forID: id) != nil {
            open(id, focusBody: true)
            return
        }
        guard !trimmed.isEmpty else { return }
        if let exact = SearchEngine.exactMatch(in: store.allNotes, title: trimmed) {
            open(exact.id, focusBody: true)
            return
        }
        create(title: trimmed)
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID }
        let next: Int
        if let current {
            next = min(max(current + delta, 0), results.count - 1)
        } else {
            next = delta > 0 ? 0 : results.count - 1
        }
        setSelection(results[next].id, explicit: true)
    }

    /// Confirms a note: it opens in the editor and its title goes into the field.
    func open(_ id: String, focusBody: Bool) {
        guard let note = store.note(forID: id) else { return }
        setSelection(id, explicit: true)
        if !echoing { restoreQuery = listQuery }
        echoing = true
        query = note.title
        if focusBody { pendingFocus = .body }
    }

    /// Cmd-N: an empty field, full list, nothing selected.
    func newNote() {
        flushSave()
        echoing = false
        query = ""
        listQuery = ""
        setSelection(nil, explicit: false)
        refresh()
        pendingFocus = .field
    }

    /// Cmd-L / Cmd-F.
    func focusField() {
        pendingFocus = .field
    }

    /// Escape: back to the field, nothing selected.
    func escape() {
        flushSave()
        if echoing {
            echoing = false
            query = restoreQuery
            listQuery = restoreQuery
            refresh()
        }
        setSelection(nil, explicit: false)
        pendingFocus = .field
    }

    func focusHandled() {
        pendingFocus = nil
    }

    // MARK: - Notes

    private func create(title: String) {
        flushSave()
        do {
            let note = try store.create(title: title)
            echoing = false
            query = note.title
            listQuery = note.title
            refresh()
            setSelection(note.id, explicit: true)
            pendingFocus = .body
            onLocalChange?(4)
        } catch NoteStore.StoreError.exists {
            if let existing = SearchEngine.exactMatch(in: store.allNotes, title: title) {
                open(existing.id, focusBody: true)
            }
        } catch NoteStore.StoreError.invalidTitle {
            showNotice("That title can’t be used as a file name.")
        } catch {
            showNotice("Couldn’t create the note: \(error.localizedDescription)")
        }
    }

    func bodyChanged(_ text: String) {
        guard let id = selectedID, let note = store.setBody(text, for: id) else { return }
        if let index = results.firstIndex(where: { $0.id == id }) { results[index] = note }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.commitSave()
        }
    }

    /// Writes any pending edit right now (selection change, backgrounding, sync).
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        commitSave()
    }

    private func commitSave() {
        do {
            if try store.flushAll() { onLocalChange?(4) }
        } catch {
            showNotice("Couldn’t save: \(error.localizedDescription)")
        }
    }

    func beginRename(_ id: String) {
        flushSave()
        renamingID = id
    }

    func cancelRename() {
        renamingID = nil
    }

    /// Editing a row's title renames its file. If the name is taken, the old name stays.
    func finishRename(_ id: String, to newTitle: String) {
        guard renamingID == id else { return }
        renamingID = nil
        guard let old = store.note(forID: id) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old.title else { return }
        do {
            let renamed = try store.rename(id, to: trimmed)
            if selectedID == id {
                selectedID = renamed.id
                if echoing { query = renamed.title }
            }
            refresh()
            onLocalChange?(4)
        } catch NoteStore.StoreError.exists {
            showNotice("“\(trimmed)” already exists. Kept “\(old.title)”.")
        } catch NoteStore.StoreError.invalidTitle {
            showNotice("That title can’t be used as a file name. Kept “\(old.title)”.")
        } catch {
            showNotice("Couldn’t rename: \(error.localizedDescription)")
        }
    }

    /// Moves the note to `Notes/.Trash` and offers Undo for a few seconds.
    func delete(_ id: String) {
        flushSave()
        do {
            let record = try store.trash(id)
            if selectedID == id {
                if echoing {
                    echoing = false
                    query = restoreQuery
                    listQuery = restoreQuery
                }
                setSelection(nil, explicit: false)
            }
            if renamingID == id { renamingID = nil }
            refresh()
            undo = UndoInfo(title: record.note.title, record: record)
            undoTask?.cancel()
            undoTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.undo = nil
            }
            onLocalChange?(12)
        } catch {
            showNotice("Couldn’t delete: \(error.localizedDescription)")
        }
    }

    func undoDelete() {
        guard let info = undo else { return }
        undo = nil
        undoTask?.cancel()
        do {
            let note = try store.restore(info.record)
            refresh()
            open(note.id, focusBody: false)
        } catch {
            showNotice("Couldn’t restore “\(info.title)”.")
        }
    }

    // MARK: - Sync callbacks

    func syncFinished(_ summary: SyncSummary) {
        refresh()
        if let conflict = summary.conflicts.first {
            let more = summary.conflicts.count > 1 ? " (+\(summary.conflicts.count - 1) more)" : ""
            showNotice("Conflict in “\(conflict.title)”: Dropbox copy saved as “\(conflict.copyTitle)”.\(more)", seconds: 10)
        }
    }

    // MARK: - Internals

    /// Re-runs the search against the in-memory index. Cheap enough to call on every keystroke.
    func refresh() {
        results = SearchEngine.filter(store.allNotes, query: listQuery, sort: settings.sortMode)
        if let id = selectedID, store.note(forID: id) == nil {
            selectedID = nil
            selectionIsExplicit = false
        }
        tick &+= 1
    }

    private func setSelection(_ id: String?, explicit: Bool) {
        if id != selectedID { flushSave() }
        selectedID = id
        selectionIsExplicit = explicit && id != nil
        if id == nil, pendingFocus == .body { pendingFocus = nil }
    }

    /// While typing: an exact title match, or the only title that starts with the query, opens in the editor.
    /// The query text itself is left alone until the user confirms.
    private func autoSelect() {
        let q = listQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            setSelection(nil, explicit: false)
            return
        }
        let notes = store.allNotes
        if let match = SearchEngine.exactMatch(in: notes, title: q) ?? SearchEngine.uniquePrefixMatch(in: notes, query: q) {
            setSelection(match.id, explicit: false)
        } else {
            setSelection(nil, explicit: false)
        }
    }

    private func showNotice(_ text: String, seconds: Double = 6) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
