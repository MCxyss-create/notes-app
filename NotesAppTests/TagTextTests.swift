import XCTest
@testable import NotesApp

final class TagTextTests: XCTestCase {
    func testParseCleansAndDeduplicates() {
        XCTAssertEqual(TagText.parse("Школа, #сервер ,  школа; Ресейл,,"), ["школа", "сервер", "ресейл"])
    }

    func testDisplay() {
        XCTAssertEqual(TagText.display(["школа", "сервер"]), "#школа #сервер")
        XCTAssertEqual(TagText.display([]), "")
    }
}
