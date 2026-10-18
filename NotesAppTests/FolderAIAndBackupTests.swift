import XCTest
@testable import NotesApp

/// Папки в ответе ИИ, в промте, в поиске и в резервной копии.
final class FolderAIAndBackupTests: XCTestCase {
    private let now = TestCalendar.date("2026-10-16 22:24")
    private let defaults = ParseDefaults(hour: 9, minute: 0, beforeMin: 15)
    private let folders = AIControlCheck.folderItems
    private var vpn: AIKnownFolder { folders[1] }
    private var shopping: AIKnownFolder { folders[2] }

    private func parse(_ json: String, known: [AIKnownItem] = []) throws -> AIResult {
        try AIParser.parse(json, reference: now, now: now, defaults: defaults, calendar: TestCalendar.moscow,
                           known: known, folders: folders)
    }

    func testDraftGoesToKnownFolder() throws {
        let result = try parse(#"""
        {"items":[{"kind":"idea","title":"Реклама у блогеров","folder":"\#(vpn.ref)","tags":[]}],"reply":"ок"}
        """#)
        XCTAssertEqual(result.drafts.first?.folderID, vpn.uid)
        XCTAssertNil(result.drafts.first?.newFolder)
    }

    /// Незнакомая папка — без папки. Дело в папку не кладётся.
    func testUnknownFolderAndRemindersStayOut() throws {
        let result = try parse(#"""
        {"items":[
          {"kind":"note","title":"Пароль","folder":"zzzzzz"},
          {"kind":"reminder","title":"Купить домен","due":"2026-10-17T12:00:00+03:00","folder":"\#(vpn.ref)","folder_new":"Дела"}
        ],"reply":"ок"}
        """#)
        XCTAssertEqual(result.drafts.count, 2)
        XCTAssertNil(result.drafts[0].folderID)
        XCTAssertNil(result.drafts[1].folderID)
        XCTAssertNil(result.drafts[1].newFolder)
    }

    /// «в новую папку X»: новая — только если такой ещё нет; есть — в неё.
    func testNewFolderOnlyWhenMissing() throws {
        let fresh = try parse(#"{"items":[{"kind":"idea","title":"Гитара","folder":null,"folder_new":"Музыка"}],"reply":"ок"}"#)
        XCTAssertNil(fresh.drafts[0].folderID)
        XCTAssertEqual(fresh.drafts[0].newFolder, "Музыка")

        let existing = try parse(#"{"items":[{"kind":"idea","title":"Кеды","folder_new":"шопинг"}],"reply":"ок"}"#)
        XCTAssertEqual(existing.drafts[0].folderID, shopping.uid)
        XCTAssertNil(existing.drafts[0].newFolder)
    }

    /// «перенеси заметку про размер ноги в папку Шопинг» → изменение «В папку».
    func testFolderCommand() throws {
        let known = AIControlCheck.commandItems
        let result = try parse(#"""
        {"items":[],"changes":[
          {"op":"folder","id":"7f6e5d","folder":"\#(shopping.ref)"},
          {"op":"folder","id":"a1b2c3","folder":"\#(shopping.ref)"},
          {"op":"folder","id":"b7c8d9","folder":"нет такой"}
        ],"reply":"Переложил."}
        """#, known: known)
        XCTAssertEqual(result.changes.count, 1)
        XCTAssertEqual(result.changes.first?.op, .folder)
        XCTAssertEqual(result.changes.first?.target.ref, "7f6e5d")
        XCTAssertEqual(result.changes.first?.folder?.uid, shopping.uid)
        XCTAssertTrue(AIControlCheck.problems(result, expected: AIControlCheck.folderCases[1]).isEmpty)
    }

    func testControlFolderCasesCatchMistakes() throws {
        XCTAssertEqual(AIControlCheck.folderCases.count, 2)
        let right = try parse(#"{"items":[{"kind":"idea","title":"Реклама у блогеров","folder":"\#(vpn.ref)"}],"reply":"ок"}"#)
        XCTAssertEqual(AIControlCheck.problems(right, expected: AIControlCheck.folderCases[0]), [])
        let loose = try parse(#"{"items":[{"kind":"idea","title":"Реклама у блогеров","folder":null}],"reply":"ок"}"#)
        XCTAssertFalse(AIControlCheck.problems(loose, expected: AIControlCheck.folderCases[0]).isEmpty)
    }

    func testPromptListsFolders() {
        let prompt = AIPrompt.system(now: now, calendar: TestCalendar.moscow, defaultHour: 9, defaultMinute: 0,
                                     defaultBefore: 15, known: AIControlCheck.commandItems, folders: folders)
        XCTAssertTrue(prompt.contains("- \(vpn.ref) | Проекты / VPN"))
        XCTAssertTrue(prompt.contains("\"folder_new\""))
        XCTAssertTrue(prompt.contains(#"{"op":"folder""#))

        let empty = AIPrompt.system(now: now, calendar: TestCalendar.moscow, defaultHour: 9, defaultMinute: 0,
                                    defaultBefore: 15)
        XCTAssertTrue(empty.contains("Папок пока нет."))
    }

    func testKnownFoldersFromTree() {
        let projects = FolderNode(id: UUID(), name: "Проекты", parentID: nil)
        let vpnNode = FolderNode(id: UUID(), name: "VPN", parentID: projects.id)
        let list = AIKnownFolder.list([vpnNode, projects])
        XCTAssertEqual(list.map(\.path), ["Проекты", "Проекты / VPN"])
        XCTAssertEqual(list.map(\.name), ["Проекты", "VPN"])
        XCTAssertEqual(list[1].ref.count, 6)
    }

    func testSearchByFolderName() {
        let idea = SearchFields(title: "Реклама у блогеров", body: nil, rawInput: nil, tags: [], folderPath: "Проекты / VPN")
        XCTAssertTrue(SearchMatcher.matches(idea, query: "vpn"))
        XCTAssertTrue(SearchMatcher.matches(idea, query: "проекты блогеров"))
        XCTAssertFalse(SearchMatcher.matches(idea, query: "школа"))
    }

    /// Старая копия (версия 1, без папок) восстанавливается как раньше: записи «Без папки».
    func testBackupVersion1StillReads() throws {
        let json = """
        {"app":"Мысли","version":1,"exportedAt":"2026-10-17T09:00:00Z","items":[
          {"uid":"A1B2C3D4-0000-4000-8000-000000000001","kind":"idea","title":"Бот","createdAt":"2026-10-16T10:00:00Z",
           "timeGiven":true,"isDone":false,"tags":[],"isPinned":false,"source":"manual"}
        ]}
        """
        let file = try Backup.decode(Data(json.utf8))
        XCTAssertEqual(file.version, 1)
        XCTAssertEqual(file.items.count, 1)
        XCTAssertNil(file.items[0].folderID)
        XCTAssertNil(file.folders)
        XCTAssertEqual(Backup.newFolders(in: file, existing: []), [])
    }

    /// Версия 2: папки и папка записи сохраняются; при восстановлении папки — без дублей по uid.
    func testBackupVersion2WithFolders() throws {
        let projects = BackupFolder(uid: UUID(), name: "Проекты", color: "blue", symbol: "briefcase", parentID: nil,
                                    sortIndex: 0, createdAt: TestCalendar.date("2026-10-16 10:00"))
        let vpnFolder = BackupFolder(uid: UUID(), name: "VPN", color: "green", symbol: "folder", parentID: projects.uid,
                                     sortIndex: 1, createdAt: TestCalendar.date("2026-10-16 10:05"))
        let item = BackupItem(uid: UUID(), kind: "idea", title: "Реклама у блогеров", body: nil,
                              createdAt: TestCalendar.date("2026-10-16 11:00"), dueAt: nil, timeGiven: true,
                              remindBeforeMin: nil, repeatRule: nil, isDone: false, doneAt: nil, tags: [],
                              isPinned: false, rawInput: nil, source: "ai", folderID: vpnFolder.uid)

        let file = try Backup.decode(Backup.encode([item], folders: [projects, vpnFolder],
                                                   exportedAt: TestCalendar.date("2026-10-17 12:00")))
        XCTAssertEqual(file.version, 2)
        XCTAssertEqual(file.items, [item])
        XCTAssertEqual(file.folders, [projects, vpnFolder])

        let doubled = BackupFile(app: "Мысли", version: 2, exportedAt: Date(), items: [],
                                 folders: [projects, vpnFolder, vpnFolder])
        XCTAssertEqual(Backup.newFolders(in: doubled, existing: [projects.uid]).map(\.name), ["VPN"])
    }
}
