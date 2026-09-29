import XCTest
@testable import Notation

@MainActor
final class NoteStoreTests: XCTestCase {
    private var base: URL!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("NotationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func makeStore() -> NoteStore {
        let store = NoteStore(baseURL: base)
        store.load()
        return store
    }

    func testCreateWritesEmptyTxtFileNamedAfterTitle() throws {
        let store = makeStore()
        let note = try store.create(title: "Hello / World")
        XCTAssertEqual(note.filename, "Hello World.txt")
        let path = store.notesURL.appendingPathComponent("Hello World.txt").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "")
    }

    func testCreateRefusesDuplicateIgnoringCase() throws {
        let store = makeStore()
        _ = try store.create(title: "Idea")
        XCTAssertThrowsError(try store.create(title: "idea")) {
            XCTAssertEqual($0 as? NoteStore.StoreError, .exists)
        }
    }

    func testBodyIsWrittenOnFlushAndSurvivesReload() throws {
        let store = makeStore()
        let note = try store.create(title: "Draft")
        store.setBody("héllo ✓", for: note.id)
        try store.flush(note.id)
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.note(forID: "Draft.txt")?.body, "héllo ✓")
    }

    func testRenameMovesFileAndRefusesExistingTarget() throws {
        let store = makeStore()
        let a = try store.create(title: "A")
        _ = try store.create(title: "B")
        XCTAssertThrowsError(try store.rename(a.id, to: "B")) {
            XCTAssertEqual($0 as? NoteStore.StoreError, .exists)
        }
        XCTAssertNotNil(store.note(forID: "A.txt"))
        let renamed = try store.rename(a.id, to: "C")
        XCTAssertEqual(renamed.filename, "C.txt")
        XCTAssertNil(store.note(forID: "A.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.notesURL.appendingPathComponent("A.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.notesURL.appendingPathComponent("C.txt").path))
    }

    func testTrashMovesToTrashFolderAndRestoreBringsItBack() throws {
        let store = makeStore()
        let note = try store.create(title: "Gone")
        store.setBody("keep me", for: note.id)
        let record = try store.trash(note.id)
        XCTAssertNil(store.note(forID: "Gone.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.trashedURL.path))
        XCTAssertEqual(record.trashedURL.deletingLastPathComponent().lastPathComponent, ".Trash")

        _ = try store.restore(record)
        XCTAssertEqual(store.note(forID: "Gone.txt")?.body, "keep me")
    }

    func testIndexRebuildsFromFilesWhenManifestIsMissing() throws {
        let store = makeStore()
        let note = try store.create(title: "Persisted")
        store.setBody("body", for: note.id)
        try store.flushAll()
        try FileManager.default.removeItem(at: base.appendingPathComponent("notes-index.json"))
        let rebuilt = makeStore()
        XCTAssertEqual(rebuilt.count, 1)
        XCTAssertEqual(rebuilt.note(forID: "Persisted.txt")?.body, "body")
    }

    func testIgnoresHiddenNonTxtAndDropboxConflictFiles() throws {
        let store = makeStore()
        let dir = store.notesURL
        for name in [".hidden.txt", "photo.png", "Note (conflicted copy).txt", "Good.txt"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.allNotes.map(\.filename), ["Good.txt"])
    }
}
