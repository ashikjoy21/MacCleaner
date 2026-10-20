import Foundation
import XCTest
@testable import CleanerKit

final class CleanerKitTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("CleanerKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: Helpers

    @discardableResult
    func makeFile(_ relative: String, bytes: Int = 4096, age: TimeInterval = 0) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        if age > 0 {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        return url
    }

    func sqlite(_ db: URL, _ sql: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [db.path, sql]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }

    let old: TimeInterval = 60 * 24 * 3600

    func makeWhatsAppContainer(referencing paths: [String] = ["Media/111@lid/a/b/kept.jpg"],
                               thumbnails: [String] = ["Media/111@lid/c/d/thumb.thumb"]) throws -> URL {
        let container = home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let db = container.appendingPathComponent("ChatStorage.sqlite")
        var sql = """
            CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMEDIALOCALPATH VARCHAR, ZXMPPTHUMBPATH VARCHAR);
            CREATE TABLE ZWAMESSAGEDATAITEM (Z_PK INTEGER PRIMARY KEY, ZTHUMBNAILPATH VARCHAR);
            CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID VARCHAR, ZPARTNERNAME VARCHAR);
            INSERT INTO ZWACHATSESSION (ZCONTACTJID, ZPARTNERNAME) VALUES ('111@lid', 'Family');
            """
        for p in paths { sql += "INSERT INTO ZWAMEDIAITEM (ZMEDIALOCALPATH) VALUES ('\(p)');" }
        for t in thumbnails { sql += "INSERT INTO ZWAMESSAGEDATAITEM (ZTHUMBNAILPATH) VALUES ('\(t)');" }
        try sqlite(db, sql)
        return container
    }

    // MARK: WhatsApp

    func testWhatsAppListsOnlyOldUnreferencedFiles() async throws {
        _ = try makeWhatsAppContainer()
        let media = "Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media"
        try makeFile("\(media)/111@lid/a/b/kept.jpg", age: old)          // referenced by ZMEDIALOCALPATH
        try makeFile("\(media)/111@lid/c/d/thumb.thumb", age: old)       // referenced by another table's PATH column
        let orphan = try makeFile("\(media)/111@lid/e/f/orphan.mp4", bytes: 50_000, age: old)
        try makeFile("\(media)/111@lid/g/h/recent.mp4", age: 3600)       // unreferenced but too new
        try makeFile("\(media)/.DS_Store", age: old)

        let result = await WhatsAppCategory(home: home).scan()
        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.title, "Family")
        XCTAssertEqual(result.items.first?.paths.map(\.standardizedFileURL), [orphan.standardizedFileURL])
    }

    func testWhatsAppRefusesWhenDatabaseHasNoReferences() async throws {
        _ = try makeWhatsAppContainer(referencing: [], thumbnails: [])
        try makeFile("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media/1@lid/x.jpg", age: old)
        let result = await WhatsAppCategory(home: home).scan()
        XCTAssertTrue(result.items.isEmpty)
        guard case .unavailable = result.status else { return XCTFail("expected unavailable, got \(result.status)") }
    }

    func testWhatsAppMissingIsUnavailable() async {
        let result = await WhatsAppCategory(home: home).scan()
        XCTAssertFalse(result.isVisible)
    }

    func testNormalizeStoredPaths() {
        XCTAssertEqual(WhatsAppDatabase.normalize("Media/1@lid/a/b.jpg"), "1@lid/a/b.jpg")
        XCTAssertEqual(WhatsAppDatabase.normalize("/Users/x/Message/Media/1@lid/a/b.jpg"), "1@lid/a/b.jpg")
        XCTAssertNil(WhatsAppDatabase.normalize("*Gp8CL20xL3Yv"))
    }

    // MARK: Moving to Trash

    func testMoveToTrashKeepsRelativeLayout() throws {
        let base = home.appendingPathComponent("Media")
        let file = try makeFile("Media/111@lid/a/b/orphan.mp4")
        let item = CleanupItem(id: "x", title: "x", paths: [file], size: 1,
                               method: .moveToTrash(folder: "Leftovers", base: base), isSelectedByDefault: true)
        XCTAssertEqual(Cleaner.remove(item, home: home), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".Trash/Leftovers/111@lid/a/b/orphan.mp4").path))
    }

    func testMoveFolderToTrashRecreatesItEmpty() throws {
        try makeFile("tg/account-1/postbox/media/big.bin")
        let media = home.appendingPathComponent("tg/account-1/postbox/media")
        let item = CleanupItem(id: "t", title: "t", paths: [media], size: 1,
                               method: .moveToTrash(folder: "TG", base: home.appendingPathComponent("tg")), isSelectedByDefault: false)
        XCTAssertEqual(Cleaner.remove(item, home: home), [])
        XCTAssertTrue(FileSystem.isDirectory(media))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: media.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".Trash/TG/account-1/postbox/media/big.bin").path))
    }

    // MARK: Project build folders

    func testProjectArtifactsNeedAMarkerFile() throws {
        try makeFile("code/web/package.json")
        try makeFile("code/web/node_modules/react/index.js")
        try makeFile("code/web/node_modules/react/node_modules/x/index.js") // nested: must not be listed separately
        try makeFile("code/notes/build/report.txt")                        // no marker: not a build folder
        try makeFile("code/app/pubspec.yaml")
        try makeFile("code/app/.dart_tool/cache.bin")

        let found = ProjectBuildsCategory(home: home).findArtifacts(in: home.appendingPathComponent("code"))
            .map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" }
        XCTAssertEqual(Set(found), ["web/node_modules", "app/.dart_tool"])
    }

    func testStaleProjectsAreTickedActiveOnesAreNot() throws {
        try makeFile("code/old/package.json", age: old)
        try makeFile("code/old/node_modules/a.js")
        try makeFile("code/new/package.json")
        try makeFile("code/new/node_modules/a.js")
        let category = ProjectBuildsCategory(home: home)
        let oldItem = category.makeItem(for: home.appendingPathComponent("code/old/node_modules"))
        let newItem = category.makeItem(for: home.appendingPathComponent("code/new/node_modules"))
        XCTAssertTrue(oldItem.isSelectedByDefault)
        XCTAssertFalse(newItem.isSelectedByDefault)
        XCTAssertEqual(oldItem.title, "old")
    }

    // MARK: Docker

    func testDockerSizeParsing() {
        XCTAssertEqual(DockerCategory.parseSize("17.05GB (51%)"), 17_050_000_000)
        XCTAssertEqual(DockerCategory.parseSize("883.7MB"), 883_700_000)
        XCTAssertEqual(DockerCategory.parseSize("0B"), 0)
    }

    func testDockerItemsSkipEmptyAndLeaveVolumesUnticked() {
        let output = """
            {"Active":"4","Reclaimable":"3.386GB (100%)","Size":"3.386GB","TotalCount":"10","Type":"Images"}
            {"Active":"13","Reclaimable":"0B (0%)","Size":"14.17MB","TotalCount":"13","Type":"Containers"}
            {"Active":"9","Reclaimable":"883.7MB (79%)","Size":"1.115GB","TotalCount":"16","Type":"Local Volumes"}
            """
        let items = DockerCategory.items(fromDockerDF: output)
        XCTAssertEqual(items.map(\.id), ["docker:images", "docker:volumes"])
        XCTAssertEqual(items.last?.isSelectedByDefault, false)
        XCTAssertEqual(items.first?.method, .command(["docker", "image", "prune", "-a", "-f"]))
    }

    // MARK: Folder caches

    func testFolderCategorySkipsMissingAndTinyFolders() async throws {
        try makeFile(".npm/_cacache/big.bin", bytes: 3_000_000)
        try makeFile("Library/Caches/pip/tiny.bin", bytes: 10)
        let result = await FolderListCategory.developerCaches(home: home).scan()
        XCTAssertEqual(result.items.map(\.title), ["npm"])
        XCTAssertEqual(result.items.first?.method, .delete)
    }
}
