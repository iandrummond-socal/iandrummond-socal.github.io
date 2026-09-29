import XCTest
@testable import Notation

final class SearchEngineTests: XCTestCase {
    private func note(_ title: String, _ body: String = "", age: TimeInterval = 0) -> Note {
        Note(filename: title + ".txt", body: body, modified: Date(timeIntervalSince1970: 1_000_000 - age))
    }

    func testEmptyQueryShowsAllNewestFirst() {
        let notes = [note("Old", age: 100), note("New", age: 1), note("Mid", age: 50)]
        let result = SearchEngine.filter(notes, query: "", sort: .modified)
        XCTAssertEqual(result.map(\.title), ["New", "Mid", "Old"])
    }

    func testTitleSortIsAlphabetical() {
        let notes = [note("banana"), note("Apple"), note("cherry")]
        let result = SearchEngine.filter(notes, query: "  ", sort: .title)
        XCTAssertEqual(result.map(\.title), ["Apple", "banana", "cherry"])
    }

    func testAllTokensMustMatchTitleOrBodyCaseInsensitively() {
        let notes = [
            note("Groceries", "milk and EGGS"),
            note("Todo", "buy milk"),
            note("Eggs recipe", "whisk"),
        ]
        let result = SearchEngine.filter(notes, query: "MILK eggs", sort: .modified)
        XCTAssertEqual(result.map(\.title), ["Groceries"])
    }

    func testRankingTitlePrefixThenTitleContainsThenBody() {
        let notes = [
            note("Body hit", "about plans", age: 1),
            note("Master plan", age: 2),
            note("Plan B", age: 3),
        ]
        let result = SearchEngine.filter(notes, query: "plan", sort: .modified)
        XCTAssertEqual(result.map(\.title), ["Plan B", "Master plan", "Body hit"])
    }

    func testTieBreakByModifiedWithinRank() {
        let notes = [note("Plan old", age: 100), note("Plan new", age: 1)]
        let result = SearchEngine.filter(notes, query: "plan", sort: .modified)
        XCTAssertEqual(result.map(\.title), ["Plan new", "Plan old"])
    }

    func testExactMatchIgnoresCaseAndCleansTitle() {
        let notes = [note("Foo Bar"), note("Foobar")]
        XCTAssertEqual(SearchEngine.exactMatch(in: notes, title: "foo bar")?.title, "Foo Bar")
        XCTAssertEqual(SearchEngine.exactMatch(in: notes, title: "  Foo   Bar ")?.title, "Foo Bar")
        XCTAssertNil(SearchEngine.exactMatch(in: notes, title: "Foo"))
    }

    func testUniquePrefixMatch() {
        let notes = [note("Alpha"), note("Alpine"), note("Beta")]
        XCTAssertEqual(SearchEngine.uniquePrefixMatch(in: notes, query: "be")?.title, "Beta")
        XCTAssertNil(SearchEngine.uniquePrefixMatch(in: notes, query: "al"))
        XCTAssertNil(SearchEngine.uniquePrefixMatch(in: notes, query: "zzz"))
        XCTAssertNil(SearchEngine.uniquePrefixMatch(in: notes, query: ""))
    }

    func testFewThousandNotesFilterQuickly() {
        let notes = (0..<3000).map { note("Note \($0)", "lorem ipsum dolor sit amet \($0)") }
        measure {
            _ = SearchEngine.filter(notes, query: "note 29 lorem", sort: .modified)
        }
    }
}
