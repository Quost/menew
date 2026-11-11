import AppKit
import XCTest
@testable import Menew

// Janela de atualização: notas longas rolam em vez de esticar a janela além da tela
@MainActor
final class UpdaterNotesTests: XCTestCase {
    func testLongNotesScrollWithinMaxHeight() {
        let long = Array(repeating: "• A long release note line that wraps across the width of the update window.", count: 80).joined(separator: "\n")
        let v = UpdaterModel.notesView(long, maxHeight: 320)
        XCTAssertEqual(v.frame.height, 320)
        XCTAssertTrue(v is NSScrollView)
        let doc = (v as? NSScrollView)?.documentView
        XCTAssertGreaterThan(doc?.frame.height ?? 0, 320, "o texto continua inteiro, rolando")
    }

    func testShortNotesKeepTheirSize() {
        let v = UpdaterModel.notesView("Fixed\n• One small fix.", maxHeight: 320)
        XCTAssertLessThan(v.frame.height, 120)
        XCTAssertGreaterThan(v.frame.height, 20)
    }
}
