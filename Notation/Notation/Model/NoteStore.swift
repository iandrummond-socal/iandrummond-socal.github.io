import Foundation

/// JSON manifest kept next to (not inside) the notes folder. It is a cache, never the source of truth:
/// if it is missing or corrupt the index is rebuilt from the `.txt` files.
struct SyncManifest: Codable {
    struct Entry: Codable {
        var path: String
        var title: String
        var mtime: Date
        var rev: String?
        var dirty: Bool
        var snippet: String
    }
    var version = 1
    var entries: [Entry] = []
    var pendingDeletes: [PendingDelete] = []
}

struct PendingDelete: Codable, Equatable {
    var filename: String
    var requested: Date
}

/// Local folder of `.txt` files (Application Support/Notes) plus an in-memory index of every note.
/// One note, one file: the filename is the title, the file contents are the body.
@MainActor
final class NoteStore {
    enum StoreError: Error, Equatable {
        case invalidTitle
        case exists
        case missing
    }

    struct TrashRecord {
        var note: Note
        var trashedURL: URL
        var queuedRemoteDelete: Bool
    }

    let notesURL: URL
    let trashURL: URL
    private let manifestURL: URL
    private let fm = FileManager.default

    private var notes: [String: Note] = [:]
    private var unflushed: Set<String> = []
    private(set) var pendingDeletes: [PendingDelete] = []

    /// - Parameter baseURL: parent of the `Notes` folder; defaults to Application Support. Tests pass a temp directory.
    init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        notesURL = base.appendingPathComponent("Notes", isDirectory: true)
        trashURL = notesURL.appendingPathComponent(".Trash", isDirectory: true)
        manifestURL = base.appendingPathComponent("notes-index.json")
    }

    // MARK: - Reading

    var allNotes: [Note] { Array(notes.values) }
    var count: Int { notes.count }

    func note(forID filename: String) -> Note? { notes[filename.lowercased()] }

    /// Scans the folder and merges in what the manifest knows about sync state.
    func load() {
        try? fm.createDirectory(at: trashURL, withIntermediateDirectories: true)
        let manifest = readManifest()
        pendingDeletes = manifest.pendingDeletes
        let known = Dictionary(manifest.entries.map { ($0.path.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        let urls = (try? fm.contentsOfDirectory(
            at: notesURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [String: Note] = [:]
        for url in urls {
            let name = url.lastPathComponent
            guard FilenameRules.isNoteFilename(name) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let data = try? Data(contentsOf: url) else { continue }
            let mtime = values?.contentModificationDate ?? Date()
            let entry = known[name.lowercased()]
            var note = Note(filename: name, body: String(decoding: data, as: UTF8.self), modified: mtime, rev: entry?.rev, dirty: true)
            if let entry {
                // A file whose mtime moved since we last recorded it was edited behind our back: treat it as unsynced.
                note.dirty = entry.dirty || abs(entry.mtime.timeIntervalSince(mtime)) > 2
            }
            loaded[note.key] = note
        }
        notes = loaded
        unflushed = []
        persist()
    }

    // MARK: - Local edits

    func create(title: String) throws -> Note {
        guard let filename = FilenameRules.filename(forTitle: title) else { throw StoreError.invalidTitle }
        guard notes[filename.lowercased()] == nil else { throw StoreError.exists }
        try Data().write(to: fileURL(filename), options: .atomic)
        var note = Note(filename: filename, body: "", modified: Date(), rev: nil, dirty: true)
        note.version = 1
        notes[note.key] = note
        persist()
        return note
    }

    /// Updates the in-memory note immediately (so search sees it); the file write follows via `flush`.
    @discardableResult
    func setBody(_ body: String, for filename: String) -> Note? {
        let key = filename.lowercased()
        guard var note = notes[key] else { return nil }
        guard note.body != body else { return note }
        note.body = body
        note.modified = Date()
        note.dirty = true
        note.version += 1
        notes[key] = note
        unflushed.insert(key)
        return note
    }

    func flush(_ filename: String) throws {
        let key = filename.lowercased()
        guard unflushed.contains(key), let note = notes[key] else { return }
        try write(note)
        unflushed.remove(key)
        persist()
    }

    /// Writes every edited note to disk. Returns whether anything was written.
    @discardableResult
    func flushAll() throws -> Bool {
        guard !unflushed.isEmpty else { return false }
        var firstError: Error?
        for key in unflushed {
            guard let note = notes[key] else { continue }
            do { try write(note); unflushed.remove(key) } catch { firstError = firstError ?? error }
        }
        persist()
        if let firstError { throw firstError }
        return true
    }

    /// Renames the file. Refuses (and changes nothing) if another note already has the target name.
    func rename(_ filename: String, to newTitle: String) throws -> Note {
        guard let newName = FilenameRules.filename(forTitle: newTitle) else { throw StoreError.invalidTitle }
        let oldKey = filename.lowercased()
        guard var note = notes[oldKey] else { throw StoreError.missing }
        if newName == note.filename { return note }
        let newKey = newName.lowercased()
        if newKey != oldKey, notes[newKey] != nil { throw StoreError.exists }

        try flush(note.filename)
        note = notes[oldKey] ?? note
        if newKey == oldKey {
            // Case-only rename: go through a temporary name so case-insensitive volumes accept it.
            let temp = notesURL.appendingPathComponent(UUID().uuidString + ".tmp")
            try fm.moveItem(at: fileURL(note.filename), to: temp)
            try fm.moveItem(at: temp, to: fileURL(newName))
        } else {
            try fm.moveItem(at: fileURL(note.filename), to: fileURL(newName))
        }
        if note.rev != nil {
            pendingDeletes.append(PendingDelete(filename: note.filename, requested: Date()))
            note.rev = nil
        }
        notes.removeValue(forKey: oldKey)
        note.filename = newName
        note.dirty = true
        note.version += 1
        notes[newKey] = note
        persist()
        return note
    }

    /// Moves the file into `Notes/.Trash`. Nothing is hard-deleted here.
    func trash(_ filename: String) throws -> TrashRecord {
        let key = filename.lowercased()
        try flush(filename)
        guard let note = notes[key] else { throw StoreError.missing }
        let destination = uniqueTrashURL(for: note.filename)
        try fm.moveItem(at: fileURL(note.filename), to: destination)
        var queued = false
        if note.rev != nil {
            pendingDeletes.append(PendingDelete(filename: note.filename, requested: Date()))
            queued = true
        }
        notes.removeValue(forKey: key)
        persist()
        return TrashRecord(note: note, trashedURL: destination, queuedRemoteDelete: queued)
    }

    func restore(_ record: TrashRecord) throws -> Note {
        let key = record.note.key
        guard notes[key] == nil else { throw StoreError.exists }
        try fm.moveItem(at: record.trashedURL, to: fileURL(record.note.filename))
        if record.queuedRemoteDelete {
            pendingDeletes.removeAll { $0.filename.lowercased() == key }
        }
        notes[key] = record.note
        persist()
        return record.note
    }

    // MARK: - Sync-facing mutations (callers invoke `persist()` once at the end)

    func hasPendingDelete(_ filename: String) -> Bool {
        let key = filename.lowercased()
        return pendingDeletes.contains { $0.filename.lowercased() == key }
    }

    /// Remote deletes are held back briefly so Undo can cancel them.
    func pendingDeletes(olderThan seconds: TimeInterval) -> [PendingDelete] {
        let cutoff = Date().addingTimeInterval(-seconds)
        return pendingDeletes.filter { $0.requested <= cutoff }
    }

    func completeDelete(_ filename: String) {
        let key = filename.lowercased()
        pendingDeletes.removeAll { $0.filename.lowercased() == key }
    }

    /// Writes the server's copy locally (creating or replacing the note) and marks it in sync.
    @discardableResult
    func applyRemote(name: String, body: String, rev: String, modified: Date) throws -> Note {
        let key = name.lowercased()
        let existing = notes[key]
        // Keep the local spelling of the filename if we already have the note.
        let filename = existing?.filename ?? name
        var note = Note(filename: filename, body: body, modified: modified, rev: rev, dirty: false)
        note.version = (existing?.version ?? 0) + 1
        try write(note)
        unflushed.remove(key)
        notes[key] = note
        return note
    }

    /// Local and server content are identical; just record the revision.
    func adopt(name: String, rev: String) {
        let key = name.lowercased()
        guard var note = notes[key] else { return }
        note.rev = rev
        note.dirty = false
        notes[key] = note
    }

    func setRev(name: String, rev: String) {
        let key = name.lowercased()
        guard var note = notes[key] else { return }
        note.rev = rev
        notes[key] = note
    }

    /// After a successful upload. If the note changed while the upload was in flight it stays dirty.
    func markUploaded(name: String, rev: String, version: Int) {
        let key = name.lowercased()
        guard var note = notes[key] else { return }
        note.rev = rev
        if note.version == version { note.dirty = false }
        notes[key] = note
    }

    /// The file disappeared on the server and we had no unsynced edits: move ours to Trash quietly.
    func dropRemoteDeleted(name: String) {
        let key = name.lowercased()
        guard let note = notes[key] else { return }
        let destination = uniqueTrashURL(for: note.filename)
        try? fm.moveItem(at: fileURL(note.filename), to: destination)
        notes.removeValue(forKey: key)
        unflushed.remove(key)
    }

    /// Stores the server's version of a conflicted note as `Title (Dropbox conflict DATE).txt`.
    @discardableResult
    func addConflictCopy(of note: Note, serverBody: String, date: Date) throws -> Note {
        let stamp = Self.conflictFormatter.string(from: date)
        let suffix = " (Dropbox conflict \(stamp))"
        let stem = String(note.title.prefix(FilenameRules.maxTitleLength - suffix.count)) + suffix
        var candidate = stem
        var n = 2
        while notes[(candidate + ".txt").lowercased()] != nil {
            candidate = stem + " \(n)"
            n += 1
        }
        guard let filename = FilenameRules.filename(forTitle: candidate) else { throw StoreError.invalidTitle }
        var copy = Note(filename: filename, body: serverBody, modified: date, rev: nil, dirty: true)
        copy.version = 1
        try write(copy)
        notes[copy.key] = copy
        return copy
    }

    /// Forget all server state (folder changed or account disconnected). Every note counts as unsynced again.
    func resetSyncState() {
        for key in notes.keys {
            notes[key]?.rev = nil
            notes[key]?.dirty = true
        }
        pendingDeletes = []
        persist()
    }

    func persist() {
        let entries = notes.values.map {
            SyncManifest.Entry(path: $0.filename, title: $0.title, mtime: $0.modified, rev: $0.rev, dirty: $0.dirty, snippet: String($0.body.prefix(200)))
        }
        let manifest = SyncManifest(entries: entries.sorted { $0.path < $1.path }, pendingDeletes: pendingDeletes)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    // MARK: - Helpers

    private func readManifest() -> SyncManifest {
        guard let data = try? Data(contentsOf: manifestURL) else { return SyncManifest() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SyncManifest.self, from: data)) ?? SyncManifest()
    }

    private func fileURL(_ filename: String) -> URL {
        notesURL.appendingPathComponent(filename, isDirectory: false)
    }

    private func write(_ note: Note) throws {
        let url = fileURL(note.filename)
        try Data(note.body.utf8).write(to: url, options: .atomic)
        try? fm.setAttributes([.modificationDate: note.modified], ofItemAtPath: url.path)
    }

    private func uniqueTrashURL(for filename: String) -> URL {
        var url = trashURL.appendingPathComponent(filename)
        guard fm.fileExists(atPath: url.path) else { return url }
        let stem = FilenameRules.title(fromFilename: filename)
        let stamp = Int(Date().timeIntervalSince1970)
        var n = 0
        repeat {
            let suffix = n == 0 ? "\(stamp)" : "\(stamp)-\(n)"
            url = trashURL.appendingPathComponent("\(stem) \(suffix).txt")
            n += 1
        } while fm.fileExists(atPath: url.path)
        return url
    }

    private static let conflictFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
