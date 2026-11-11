import AppKit
import XCTest
@testable import Menew

// Imagens que chegam ao clipboard num tipo de texto (Teams, Claude): viram imagem, não "âPNG…"

final class BinaryClipTests: XCTestCase {
    private func samplePNG() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testPNGBytesReadAsMacRomanTextAreAnImage() throws {
        let png = samplePNG()
        let text = try XCTUnwrap(String(data: png, encoding: .macOSRoman))
        XCTAssertTrue(text.hasPrefix("âPNG"))
        XCTAssertTrue(BinaryClip.looksBinary(text))
        let bytes = try XCTUnwrap(BinaryClip.bytes(fromText: text))
        XCTAssertEqual(bytes, png)
        let rep = try XCTUnwrap(BinaryClip.bitmap(from: bytes))
        XCTAssertEqual(rep.pixelsWide, 3)
        XCTAssertEqual(rep.pixelsHigh, 2)
    }

    func testPNGBytesReadAsLatin1AreRecovered() throws {
        let png = samplePNG()
        let text = try XCTUnwrap(String(data: png, encoding: .isoLatin1))
        XCTAssertEqual(BinaryClip.bytes(fromText: text), png)
    }

    func testRawDataSignatures() {
        XCTAssertTrue(BinaryClip.isBinary(samplePNG()))
        XCTAssertTrue(BinaryClip.isBinary(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        XCTAssertFalse(BinaryClip.isBinary(Data("hello".utf8)))
    }

    func testBrokenUTF8PNGIsBinaryButNotRecoverable() {
        let text = "\u{FFFD}PNG\r\n\u{1A}\nIHDR"
        XCTAssertTrue(BinaryClip.looksBinary(text))
        XCTAssertNil(BinaryClip.bytes(fromText: text))
    }

    func testRealTextIsNotBinary() {
        for t in ["Reunião às 14h", "GIF89a is an image format", "%PDF-1.7 explained", "ÿØÿ? just letters",
                  "https://example.com/a.png", "‰PNG"] {
            XCTAssertFalse(BinaryClip.looksBinary(t), t)
        }
        XCTAssertTrue(BinaryClip.looksBinary("abc\u{0}def"))
    }

    func testAccessibilityExplainsStaleGrantInsteadOfPromptingAgain() {
        XCTAssertFalse(AccessibilityGrant.shouldExplainStale(grantedBefore: false, promptedThisLaunch: false))
        XCTAssertTrue(AccessibilityGrant.shouldExplainStale(grantedBefore: true, promptedThisLaunch: false))
        XCTAssertTrue(AccessibilityGrant.shouldExplainStale(grantedBefore: false, promptedThisLaunch: true))
    }
}
