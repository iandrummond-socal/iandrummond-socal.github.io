import Foundation

struct RemoteFile: Equatable {
    var name: String
    var rev: String
    var serverModified: Date
}

struct RemoteContent {
    var body: String
    var rev: String
    var serverModified: Date
}

/// The small slice of Dropbox the app needs. `SwiftyDropboxAPI` is the real implementation; tests use a fake.
protocol DropboxAPI {
    /// Files (not folders) directly inside `folder`. A missing folder is created and reported as empty.
    func listFiles(in folder: String) async throws -> [RemoteFile]
    func download(_ name: String, in folder: String) async throws -> RemoteContent
    /// `rev == nil` adds a new file (fails if the name is taken); otherwise updates only if the server is still at `rev`.
    func upload(_ body: String, name: String, in folder: String, replacing rev: String?) async throws -> RemoteFile
    /// Deleting something that is already gone is not an error.
    func delete(_ name: String, in folder: String) async throws
    func listFolders(in path: String) async throws -> [String]
}

struct SyncSummary: Equatable {
    struct Conflict: Equatable {
        var title: String
        var copyTitle: String
    }
    var downloaded = 0
    var uploaded = 0
    var conflicts: [Conflict] = []
    var errors: [String] = []
}

/// One sync pass: list the Dropbox folder, then reconcile every note against the local cache.
///
/// - Server newer, no local edits → download.
/// - Local edits, server unchanged → upload.
/// - Both changed → local edit stays as `Title.txt`, server copy saved as `Title (Dropbox conflict DATE).txt`.
/// - A failure on one file does not stop the others; it is reported in `errors` and retried next pass.
@MainActor
struct SyncEngine {
    let api: DropboxAPI
    let store: NoteStore
    let folder: String
    /// Local deletes wait this long before reaching Dropbox, so Undo can cancel them.
    var deleteGrace: TimeInterval = 10
    var now: () -> Date = Date.init

    func run() async throws -> SyncSummary {
        var summary = SyncSummary()
        try store.flushAll()
        defer { store.persist() }

        let listed = try await api.listFiles(in: folder).filter { FilenameRules.isNoteFilename($0.name) }
        var remote = Dictionary(listed.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Deletes queued locally (deleted or renamed notes).
        for pending in store.pendingDeletes(olderThan: deleteGrace) {
            do {
                try await api.delete(pending.filename, in: folder)
                store.completeDelete(pending.filename)
                remote.removeValue(forKey: pending.filename.lowercased())
            } catch {
                summary.errors.append("Delete \(pending.filename): \(error.localizedDescription)")
            }
        }

        // 2. Files that exist on the server.
        for file in remote.values.sorted(by: { $0.name < $1.name }) {
            do {
                try await reconcile(file, summary: &summary)
            } catch {
                summary.errors.append("\(file.name): \(error.localizedDescription)")
            }
        }

        // 3. Notes the server does not have (new, renamed, restored, conflict copies, or deleted remotely).
        for note in store.allNotes.sorted(by: { $0.filename < $1.filename }) where remote[note.key] == nil {
            if note.rev != nil && !note.dirty {
                store.dropRemoteDeleted(name: note.filename)
                continue
            }
            do {
                try await upload(note, replacing: nil, summary: &summary)
            } catch {
                summary.errors.append("\(note.filename): \(error.localizedDescription)")
            }
        }
        return summary
    }

    private func reconcile(_ file: RemoteFile, summary: inout SyncSummary) async throws {
        guard let local = store.note(forID: file.name) else {
            if store.hasPendingDelete(file.name) { return }
            let content = try await api.download(file.name, in: folder)
            try store.applyRemote(name: file.name, body: content.body, rev: content.rev, modified: content.serverModified)
            summary.downloaded += 1
            return
        }

        if local.rev == file.rev {
            if local.dirty { try await upload(local, replacing: file.rev, summary: &summary) }
            return
        }

        // The server changed (or we have never synced this note): fetch its content.
        let content = try await api.download(file.name, in: folder)
        // If the note was edited while we were waiting, leave it for the next pass.
        guard let current = store.note(forID: file.name), current.version == local.version else { return }

        if !current.dirty && current.rev != nil {
            try store.applyRemote(name: file.name, body: content.body, rev: content.rev, modified: content.serverModified)
            summary.downloaded += 1
            return
        }
        if current.body == content.body {
            store.adopt(name: current.filename, rev: content.rev)
            return
        }

        // Both sides changed: keep the local edit, preserve the server copy next to it.
        let copy = try store.addConflictCopy(of: current, serverBody: content.body, date: now())
        store.setRev(name: current.filename, rev: content.rev)
        summary.conflicts.append(.init(title: current.title, copyTitle: copy.title))
        if let updated = store.note(forID: current.filename) {
            try await upload(updated, replacing: content.rev, summary: &summary)
        }
    }

    private func upload(_ note: Note, replacing rev: String?, summary: inout SyncSummary) async throws {
        let uploaded = try await api.upload(note.body, name: note.filename, in: folder, replacing: rev)
        // Dropbox may answer an out-of-date update with a differently named "conflicted copy"; leave the note dirty.
        guard uploaded.name.lowercased() == note.filename.lowercased() else {
            throw SyncFailure.conflictedCopy
        }
        store.markUploaded(name: note.filename, rev: uploaded.rev, version: note.version)
        summary.uploaded += 1
    }
}

enum SyncFailure: LocalizedError {
    case conflictedCopy

    var errorDescription: String? {
        switch self {
        case .conflictedCopy: return "the server changed during upload; will retry"
        }
    }
}
