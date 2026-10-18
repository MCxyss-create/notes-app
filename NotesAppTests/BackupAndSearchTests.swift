import XCTest
@testable import NotesApp

final class BackupAndSearchTests: XCTestCase {
    private func sample(_ title: String, uid: UUID = UUID()) -> BackupItem {
        BackupItem(uid: uid, kind: "reminder", title: title, body: "подробности",
                   createdAt: TestCalendar.date("2026-10-16 10:00"), dueAt: TestCalendar.date("2026-10-17 09:00"),
                   timeGiven: false, remindBeforeMin: 15, repeatRule: "weekly", isDone: false, doneAt: nil,
                   tags: ["школа"], isPinned: true, rawInput: "завтра подойти к учителю", source: "ai")
    }

    func testBackupRoundTrip() throws {
        let items = [sample("Подойти к учителю"), sample("Сдать пробник")]
        let file = try Backup.decode(Backup.encode(items, exportedAt: TestCalendar.date("2026-10-17 12:00")))

        XCTAssertEqual(file.app, "Мысли")
        XCTAssertEqual(file.version, Backup.version)
        XCTAssertEqual(file.items, items)
    }

    /// Восстановление добавляет только новые записи и не двоит повторы внутри файла.
    func testImportSkipsExisting() {
        let known = UUID()
        let fresh = UUID()
        let file = BackupFile(app: "Мысли", version: 1, exportedAt: Date(),
                              items: [sample("уже есть", uid: known), sample("новая", uid: fresh), sample("дубль", uid: fresh)])

        let added = Backup.newItems(in: file, existing: [known])

        XCTAssertEqual(added.map(\.title), ["новая"])
    }

    func testBadFileThrows() {
        XCTAssertThrowsError(try Backup.decode(Data("{\"привет\": 1}".utf8)))
    }

    private func fields(_ title: String, body: String? = nil, tags: [String] = []) -> SearchFields {
        SearchFields(title: title, body: body, rawInput: nil, tags: tags)
    }

    func testSearchByWordsAndTags() {
        let teacher = fields("Подойти к учителю", body: "Спросить про пробник", tags: ["школа"])

        XCTAssertTrue(SearchMatcher.matches(teacher, query: "учител"))
        XCTAssertTrue(SearchMatcher.matches(teacher, query: "пробник учителю"))
        XCTAssertTrue(SearchMatcher.matches(teacher, query: "#шко"))
        XCTAssertTrue(SearchMatcher.matches(teacher, query: "школа"))
        XCTAssertFalse(SearchMatcher.matches(teacher, query: "#сервер"))
        XCTAssertFalse(SearchMatcher.matches(teacher, query: "учителю сервер"))
        XCTAssertFalse(SearchMatcher.matches(teacher, query: "   "))
    }

    func testSearchIgnoresYo() {
        XCTAssertTrue(SearchMatcher.matches(fields("Тёмная тема"), query: "темная"))
        XCTAssertTrue(SearchMatcher.matches(fields("Темная тема"), query: "тёмная"))
    }
}
