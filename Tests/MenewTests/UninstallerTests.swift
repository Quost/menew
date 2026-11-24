import XCTest
@testable import Menew

// Desinstalador: nome e identificador vêm do app arrastado e não podem escapar da Library nem casar com tudo.

final class UninstallerTests: XCTestCase {
    private let lib = URL(fileURLWithPath: "/Users/ana/Library")

    func testRejectsPathTraversalInName() {
        XCTAssertNil(Uninstaller.safeComponents(id: "com.example.App", name: "../../Documents").name)
    }

    func testRejectsSlashInNameAndId() {
        XCTAssertNil(Uninstaller.safeComponents(id: "com.example.App", name: "a/b").name)
        XCTAssertNil(Uninstaller.safeComponents(id: "com.example/App", name: "Example").id)
    }

    func testRejectsShortOrEmptyValues() {
        XCTAssertNil(Uninstaller.safeComponents(id: "a", name: "Example").id)
        XCTAssertNil(Uninstaller.safeComponents(id: "", name: "").id)
        XCTAssertNil(Uninstaller.safeComponents(id: "", name: "").name)
        XCTAssertNil(Uninstaller.safeComponents(id: "com.example.App", name: "abc").name)
    }

    func testRejectsIdWithoutDotOrWithOddCharacters() {
        XCTAssertNil(Uninstaller.safeComponents(id: "example", name: "Example").id)
        XCTAssertNil(Uninstaller.safeComponents(id: "com..example", name: "Example").id)
        XCTAssertNil(Uninstaller.safeComponents(id: "com.exa mple.App", name: "Example").id)
    }

    func testAcceptsNormalValues() {
        let r = Uninstaller.safeComponents(id: "com.example.App", name: "Example")
        XCTAssertEqual(r.id, "com.example.App")
        XCTAssertEqual(r.name, "Example")
    }

    func testInsideLibrary() {
        XCTAssertTrue(Uninstaller.isInside(lib.appendingPathComponent("Caches/com.example.App"), lib))
        XCTAssertFalse(Uninstaller.isInside(lib.appendingPathComponent("Application Support/../../Documents"), lib))
        XCTAssertFalse(Uninstaller.isInside(lib, lib))
    }
}
