import XCTest
@testable import Menew

// Reconhecimento do clipboard esperto: cor, código de rastreio, link, e-mail, telefone

@MainActor
final class SmartClipTests: XCTestCase {
    private func ids(_ text: String) -> [String] { SmartClip.actions(for: text).map(\.id) }

    func testParseHexColor() throws {
        let c = try XCTUnwrap(SmartClip.parseColor("#3B82F6"))
        XCTAssertEqual([c.r, c.g, c.b], [59, 130, 246])
        XCTAssertEqual(c.hex, "#3B82F6")
        XCTAssertEqual(c.rgb, "rgb(59, 130, 246)")
        XCTAssertEqual(c.hsl, "hsl(217, 91%, 60%)")
    }

    func testParseShortHexAndRGB() throws {
        let s = try XCTUnwrap(SmartClip.parseColor(" #38f "))
        XCTAssertEqual(s.hex, "#3388FF")
        let r = try XCTUnwrap(SmartClip.parseColor("rgb(59, 130, 246)"))
        XCTAssertEqual([r.r, r.g, r.b], [59, 130, 246])
        XCTAssertEqual(try XCTUnwrap(SmartClip.parseColor("#FF0000")).hsl, "hsl(0, 100%, 50%)")
        XCTAssertEqual(try XCTUnwrap(SmartClip.parseColor("#000000")).hsl, "hsl(0, 0%, 0%)")
        XCTAssertEqual(try XCTUnwrap(SmartClip.parseColor("#fff")).hsl, "hsl(0, 0%, 100%)")
    }

    func testParseColorRejectsInvalid() {
        XCTAssertNil(SmartClip.parseColor("#12345"))
        XCTAssertNil(SmartClip.parseColor("#GGGGGG"))
        XCTAssertNil(SmartClip.parseColor("red"))
        XCTAssertNil(SmartClip.parseColor("rgb(300, 0, 0)"))
        XCTAssertNil(SmartClip.parseColor("rgb(1, 2)"))
    }

    func testColorActionsSkipTheFormatAlreadyCopied() {
        let found = ids("#3B82F6")
        XCTAssertTrue(found.contains("color.RGB"))
        XCTAssertTrue(found.contains("color.HSL"))
        XCTAssertFalse(found.contains("color.HEX"))
    }

    func testTrackingCodes() {
        let br = SmartClip.actions(for: "AB123456789BR").first { $0.id == "tracking" }
        XCTAssertEqual(br?.subtitle, "rastreamento.correios.com.br")
        let ups = SmartClip.actions(for: "1Z999AA10123456784").first { $0.id == "tracking" }
        XCTAssertEqual(ups?.subtitle, "parcelsapp.com")
        XCTAssertFalse(ids("AB12345BR").contains("tracking"))
    }

    func testLinkGetsOpenAndQRActions() {
        let found = SmartClip.actions(for: "https://example.com/path")
        XCTAssertEqual(found.map(\.id), ["link", "qr"])
        XCTAssertEqual(found.first?.subtitle, "https://example.com/path")
    }

    func testEmailAndPhone() {
        XCTAssertTrue(ids("john@example.com").contains("mail"))
        XCTAssertTrue(ids("+55 11 91234-5678").contains("phone"))
    }

    func testNothingRecognized() {
        XCTAssertTrue(SmartClip.actions(for: "").isEmpty)
        XCTAssertTrue(SmartClip.actions(for: "   \n ").isEmpty)
        XCTAssertTrue(SmartClip.actions(for: "just some ordinary words").isEmpty)
        XCTAssertTrue(SmartClip.actions(for: String(repeating: "a", count: 401)).isEmpty)
    }
}
