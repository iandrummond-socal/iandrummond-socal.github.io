import XCTest
@testable import Notation

final class FilenameRulesTests: XCTestCase {
    func testStripsPathSeparatorsAndReservedCharacters() {
        XCTAssertEqual(FilenameRules.cleanTitle("a/b\\c:d"), "abcd")
        XCTAssertEqual(FilenameRules.filename(forTitle: "what? <now>"), "what now.txt")
    }

    func testStripsLeadingDotsAndCollapsesWhitespace() {
        XCTAssertEqual(FilenameRules.cleanTitle("...hidden"), "hidden")
        XCTAssertEqual(FilenameRules.cleanTitle("  many \n  spaces\t here "), "many spaces here")
    }

    func testCapsAt120Characters() {
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(FilenameRules.cleanTitle(long)?.count, 120)
    }

    func testEmptyResultIsNil() {
        XCTAssertNil(FilenameRules.cleanTitle(" / . "))
        XCTAssertNil(FilenameRules.filename(forTitle: ""))
    }

    func testTitleFromFilename() {
        XCTAssertEqual(FilenameRules.title(fromFilename: "Hello.txt"), "Hello")
        XCTAssertEqual(FilenameRules.title(fromFilename: "Hello.TXT"), "Hello")
        XCTAssertEqual(FilenameRules.title(fromFilename: "a.b.txt"), "a.b")
    }

    func testWhichFilesAreNotes() {
        XCTAssertTrue(FilenameRules.isNoteFilename("Note.txt"))
        XCTAssertFalse(FilenameRules.isNoteFilename(".hidden.txt"))
        XCTAssertFalse(FilenameRules.isNoteFilename("image.png"))
        XCTAssertFalse(FilenameRules.isNoteFilename("Note (conflicted copy 2024).txt"))
        XCTAssertFalse(FilenameRules.isNoteFilename("Note (Panda's conflicted copy).txt"))
        XCTAssertFalse(FilenameRules.isNoteFilename("Note.conflict"))
    }
}
