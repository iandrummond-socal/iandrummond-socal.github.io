import XCTest
@testable import Notation

/// In-memory stand-in for Dropbox.
final class FakeDropbox: DropboxAPI {
    struct File { var body: String; var rev: String; var modified: Date }
    var files: [String: File] = [:]
    private var counter = 0

    func put(_ name: String, _ body: String) {
        counter += 1
        files[name] = File(body: body, rev: "rev\(counter)", modified: Date())
    }

    func listFiles(in folder: String) async throws -> [RemoteFile] {
        files.map { RemoteFile(name: $0.key, rev: $0.value.rev, serverModified: $0.value.modified) }
    }

    func download(_ name: String, in folder: String) async throws -> RemoteContent {
        let f = files[name]!
        return RemoteContent(body: f.body, rev: f.rev, serverModified: f.modified)
    }

    func upload(_ body: String, name: String, in folder: String, replacing rev: String?) async throws -> RemoteFile {
        if rev == nil, files[name] != nil { throw NSError(domain: "conflict", code: 409) }
        put(name, body)
        let f = files[name]!
        return RemoteFile(name: name, rev: f.rev, serverModified: f.modified)
    }

    func delete(_ name: String, in folder: String) async throws { files.removeValue(forKey: name) }
    func listFolders(in path: String) async throws -> [String] { [] }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    private var base: URL!
    private var store: NoteStore!
    private var api: FakeDropbox!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("NotationSync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        store = NoteStore(baseURL: base)
        store.load()
        api = FakeDropbox()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func sync() async throws -> SyncSummary {
        var engine = SyncEngine(api: api, store: store, folder: "")
        engine.deleteGrace = 0
        return try await engine.run()
    }

    func testDownloadsNewRemoteFilesAndIgnoresOthers() async throws {
        api.put("Remote.txt", "hello")
        api.put("photo.png", "x")
        api.put("Note (conflicted copy).txt", "x")
        let summary = try await sync()
        XCTAssertEqual(summary.downloaded, 1)
        XCTAssertEqual(store.allNotes.map(\.filename), ["Remote.txt"])
        XCTAssertEqual(store.note(forID: "Remote.txt")?.dirty, false)
    }

    func testUploadsNewLocalNote() async throws {
        let note = try store.create(title: "Local")
        store.setBody("draft", for: note.id)
        _ = try await sync()
        XCTAssertEqual(api.files["Local.txt"]?.body, "draft")
        XCTAssertEqual(store.note(forID: "Local.txt")?.dirty, false)
        XCTAssertNotNil(store.note(forID: "Local.txt")?.rev)
    }

    func testRemoteChangeWithoutLocalEditsDownloads() async throws {
        api.put("N.txt", "v1")
        _ = try await sync()
        api.put("N.txt", "v2")
        _ = try await sync()
        XCTAssertEqual(store.note(forID: "N.txt")?.body, "v2")
    }

    func testLocalEditUploadsOverKnownRevision() async throws {
        api.put("N.txt", "v1")
        _ = try await sync()
        store.setBody("local", for: "N.txt")
        _ = try await sync()
        XCTAssertEqual(api.files["N.txt"]?.body, "local")
    }

    func testConflictKeepsLocalAndSavesServerCopy() async throws {
        api.put("N.txt", "v1")
        _ = try await sync()
        store.setBody("local edit", for: "N.txt")
        api.put("N.txt", "server edit")

        let summary = try await sync()
        XCTAssertEqual(summary.conflicts.count, 1)
        XCTAssertEqual(store.note(forID: "N.txt")?.body, "local edit")
        let copy = store.allNotes.first { $0.title.hasPrefix("N (Dropbox conflict ") }
        XCTAssertEqual(copy?.body, "server edit")
        // Both end up on the server too.
        XCTAssertEqual(api.files["N.txt"]?.body, "local edit")
        XCTAssertEqual(api.files[copy!.filename]?.body, "server edit")
    }

    func testRemoteDeletionRemovesUnchangedLocalNote() async throws {
        api.put("N.txt", "v1")
        _ = try await sync()
        api.files.removeValue(forKey: "N.txt")
        _ = try await sync()
        XCTAssertNil(store.note(forID: "N.txt"))
    }

    func testLocalDeleteAndRenamePropagate() async throws {
        api.put("Old.txt", "x")
        api.put("Gone.txt", "y")
        _ = try await sync()
        _ = try store.rename("Old.txt", to: "New")
        _ = try store.trash("Gone.txt")
        _ = try await sync()
        XCTAssertNil(api.files["Old.txt"])
        XCTAssertNil(api.files["Gone.txt"])
        XCTAssertEqual(api.files["New.txt"]?.body, "x")
    }

    func testIdenticalContentWithNoBaseRevisionAdoptsWithoutConflict() async throws {
        let note = try store.create(title: "Same")
        store.setBody("text", for: note.id)
        api.put("Same.txt", "text")
        let summary = try await sync()
        XCTAssertTrue(summary.conflicts.isEmpty)
        XCTAssertEqual(store.note(forID: "Same.txt")?.dirty, false)
    }
}
