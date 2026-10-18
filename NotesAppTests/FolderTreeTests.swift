import XCTest
@testable import NotesApp

/// Папки: путь, глубина до 3 уровней, запрет круга, уникальные имена, удаление без потерь.
final class FolderTreeTests: XCTestCase {
    private let projects = FolderNode(id: UUID(), name: "Проекты", parentID: nil, sortIndex: 0)
    private lazy var vpn = FolderNode(id: UUID(), name: "VPN", parentID: projects.id, sortIndex: 0)
    private lazy var ads = FolderNode(id: UUID(), name: "Реклама", parentID: vpn.id, sortIndex: 0)
    private let school = FolderNode(id: UUID(), name: "Школа", parentID: nil, sortIndex: 1)
    private lazy var nodes = [ads, school, vpn, projects]

    func testPathAndDepth() {
        XCTAssertEqual(FolderTree.pathText(ads.id, in: nodes), "Проекты / VPN / Реклама")
        XCTAssertEqual(FolderTree.pathText(school.id, in: nodes), "Школа")
        XCTAssertEqual(FolderTree.pathText(UUID(), in: nodes), "")
        XCTAssertEqual(FolderTree.depth(of: nil, in: nodes), 0)
        XCTAssertEqual(FolderTree.depth(of: projects.id, in: nodes), 1)
        XCTAssertEqual(FolderTree.depth(of: ads.id, in: nodes), 3)
        XCTAssertEqual(FolderTree.height(of: projects.id, in: nodes), 3)
        XCTAssertEqual(FolderTree.height(of: school.id, in: nodes), 1)
    }

    func testTreeLinesInOrder() {
        let lines = FolderTree.lines(nodes)
        XCTAssertEqual(lines.map(\.node.name), ["Проекты", "VPN", "Реклама", "Школа"])
        XCTAssertEqual(lines.map(\.level), [0, 1, 2, 0])
        XCTAssertEqual(FolderTree.children(of: nil, in: nodes).map(\.name), ["Проекты", "Школа"])
    }

    /// Не больше 3 уровней: в «Рекламу» новую папку не положить.
    func testMaxThreeLevels() {
        XCTAssertTrue(FolderTree.canCreate(in: nil, nodes: nodes))
        XCTAssertTrue(FolderTree.canCreate(in: vpn.id, nodes: nodes))
        XCTAssertFalse(FolderTree.canCreate(in: ads.id, nodes: nodes))
        // «Проекты» с двумя уровнями внутри в «Школу» не влезут, «Реклама» — влезет.
        XCTAssertFalse(FolderTree.canMove(projects.id, to: school.id, in: nodes))
        XCTAssertTrue(FolderTree.canMove(ads.id, to: school.id, in: nodes))
        XCTAssertTrue(FolderTree.canMove(vpn.id, to: nil, in: nodes))
    }

    /// Папку нельзя положить в саму себя или в свою подпапку.
    func testNoCycles() {
        XCTAssertFalse(FolderTree.canMove(projects.id, to: projects.id, in: nodes))
        XCTAssertFalse(FolderTree.canMove(projects.id, to: vpn.id, in: nodes))
        XCTAssertFalse(FolderTree.canMove(projects.id, to: ads.id, in: nodes))
        XCTAssertEqual(FolderTree.descendants(of: projects.id, in: nodes), [vpn.id, ads.id])
    }

    /// Битая база с кругом не вешает приложение: папки считаются верхними.
    func testBrokenCycleDoesNotHang() {
        let a = UUID()
        let b = UUID()
        let broken = [FolderNode(id: a, name: "А", parentID: b), FolderNode(id: b, name: "Б", parentID: a)]
        XCTAssertEqual(FolderTree.lines(broken).count, 2)
        XCTAssertEqual(FolderTree.pathText(a, in: broken), "А")
    }

    /// Имя уникально среди соседей: без учёта регистра, «ё» = «е». У разных родителей — можно.
    func testUniqueNamesAmongSiblings() {
        XCTAssertTrue(FolderTree.isNameTaken("  проекты ", in: nil, nodes: nodes))
        XCTAssertTrue(FolderTree.isNameTaken("vpn", in: projects.id, nodes: nodes))
        XCTAssertFalse(FolderTree.isNameTaken("VPN", in: nil, nodes: nodes))
        XCTAssertFalse(FolderTree.isNameTaken("Проекты", in: nil, excluding: projects.id, nodes: nodes))

        let tree = nodes + [FolderNode(id: UUID(), name: "Ёлка", parentID: nil)]
        XCTAssertTrue(FolderTree.isNameTaken("елка", in: nil, nodes: tree))
        XCTAssertEqual(FolderTree.uniqueName("Школа", in: nil, nodes: tree), "Школа 2")
        XCTAssertEqual(FolderTree.uniqueName("Музыка", in: nil, nodes: tree), "Музыка")
    }

    /// Удаление «VPN»: записи и «Реклама» переезжают в «Проекты». Совпало имя — «Реклама 2».
    func testRemovalMovesEverythingToParent() {
        let sameName = FolderNode(id: UUID(), name: "реклама", parentID: projects.id, sortIndex: 1)
        let tree = nodes + [sameName]
        let removal = FolderTree.removal(of: vpn.id, in: tree)
        XCTAssertEqual(removal.target, projects.id)
        XCTAssertEqual(removal.renamed, [ads.id: "Реклама 2"])

        // Верхний уровень: всё — в «Без папки», подпапки — наверх.
        let top = FolderTree.removal(of: projects.id, in: nodes)
        XCTAssertNil(top.target)
        XCTAssertEqual(top.renamed, [vpn.id: "VPN"])
    }

    func testCountsIncludeNestedAndLooseItems() {
        let folders: [UUID?] = [ads.id, vpn.id, nil, school.id, UUID()]
        XCTAssertEqual(FolderTree.count(in: projects.id, folderIDs: folders, nodes: nodes), 2)
        XCTAssertEqual(FolderTree.count(in: ads.id, folderIDs: folders, nodes: nodes), 1)
        XCTAssertTrue(FolderTree.isLoose(nil, in: nodes))
        XCTAssertTrue(FolderTree.isLoose(UUID(), in: nodes))
        XCTAssertFalse(FolderTree.isLoose(vpn.id, in: nodes))
    }
}
