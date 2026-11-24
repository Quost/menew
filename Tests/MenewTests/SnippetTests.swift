import XCTest
@testable import Menew

// Marcadores dos snippets: {cursor} e {input:Nome}. {date}/{clipboard} dependem do relógio e do sistema e ficam de fora.

@MainActor
final class SnippetTests: XCTestCase {
    func testExpandWithoutPlaceholdersIsUnchanged() {
        let r = SnippetStore.expandWithCursor("plain text")
        XCTAssertEqual(r.text, "plain text")
        XCTAssertEqual(r.back, 0)
        XCTAssertEqual(SnippetStore.expand("plain text"), "plain text")
    }

    func testCursorMarkerIsRemovedAndCountsCharactersAfterIt() {
        let r = SnippetStore.expandWithCursor("Hello {cursor}world")
        XCTAssertEqual(r.text, "Hello world")
        XCTAssertEqual(r.back, 5)

        let end = SnippetStore.expandWithCursor("abc{cursor}")
        XCTAssertEqual(end.text, "abc")
        XCTAssertEqual(end.back, 0)

        let multiline = SnippetStore.expandWithCursor("{cursor}\nx")
        XCTAssertEqual(multiline.text, "\nx")
        XCTAssertEqual(multiline.back, 2)
    }

    func testExpandDropsCursorAndFillsDate() {
        XCTAssertEqual(SnippetStore.expand("a{cursor}b"), "ab")
        let date = SnippetStore.expand("{date}")
        XCTAssertFalse(date.isEmpty)
        XCTAssertNotEqual(date, "{date}")
    }

    func testFieldsAreOrderedTrimmedAndUnique() {
        XCTAssertEqual(SnippetStore.fields(in: "Hi {input:Name}, {input: Age } and {input:Name}"), ["Name", "Age"])
        XCTAssertEqual(SnippetStore.fields(in: "no fields {cursor}"), [])
        XCTAssertEqual(SnippetStore.fields(in: ""), [])
    }

    func testApplyReplacesInputs() {
        XCTAssertEqual(SnippetStore.apply("Hi {input:Name}!", values: ["Name": "Ana"]), "Hi Ana!")
        XCTAssertEqual(SnippetStore.apply("{input: Name } and {input:Name}", values: ["Name": "Ana"]), "Ana and Ana")
        XCTAssertEqual(SnippetStore.apply("{input:A}-{input:B}", values: ["A": "1", "B": "2"]), "1-2")
        XCTAssertEqual(SnippetStore.apply("{input:Other}", values: ["Name": "Ana"]), "{input:Other}")
    }

    func testApplyTreatsValueLiterally() {
        XCTAssertEqual(SnippetStore.apply("{input:X}", values: ["X": "$1 & \\0"]), "$1 & \\0")
    }
}
