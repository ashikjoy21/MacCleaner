import Foundation
import XCTest
@testable import CleanerKit

final class DeepScanTests: XCTestCase {
    var home: URL!
    let old: TimeInterval = 200 * 24 * 3600

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("DeepScan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    @discardableResult
    func write(_ relative: String, bytes: Int = 4096, fill: UInt8 = 1, age: TimeInterval = 0) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: url)
        if age > 0 {
            let date = Date().addingTimeInterval(-age)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            var values = URLResourceValues()
            values.contentAccessDate = date
            var u = url
            try u.setResourceValues(values)
        }
        return url
    }

    func testAerialsKeepTheNewestVideosAndUseManifestNames() async throws {
        let aerials = "Library/Application Support/com.apple.wallpaper/aerials"
        try write("\(aerials)/videos/AAA.mov", age: 30 * 86400)
        try write("\(aerials)/videos/BBB.mov", age: 20 * 86400)
        try write("\(aerials)/videos/CCC.mov", age: 10 * 86400)
        let manifest = #"{"assets":[{"id":"AAA","accessibilityLabel":"Tahoe Sunset"}]}"#
        try write("\(aerials)/manifest/entries.json")
        try manifest.write(to: home.appendingPathComponent("\(aerials)/manifest/entries.json"), atomically: true, encoding: .utf8)

        var category = AerialWallpapersCategory(home: home)
        category.keepNewest = 2
        let items = await category.scan().items
        XCTAssertEqual(items.filter(\.isSelectedByDefault).map(\.title), ["Tahoe Sunset"], "only the oldest is ticked")
        XCTAssertEqual(items.count, 3)
    }

    func testTrashListsEntriesUnticked() async throws {
        try write(".Trash/old.zip", bytes: 10_000)
        let result = await TrashCategory(home: home).scan()
        XCTAssertEqual(result.items.map(\.title), ["old.zip"])
        XCTAssertFalse(result.items[0].isSelectedByDefault)
        XCTAssertEqual(result.items[0].method, .delete)
    }

    func testChromeCachesAreListedPerProfileWithNames() async throws {
        let chrome = "Library/Application Support/Google/Chrome"
        try write("\(chrome)/Default/Service Worker/CacheStorage/blob", bytes: 25_000_000)
        try write("\(chrome)/Default/IndexedDB/keep.db", bytes: 25_000_000)
        try #"{"profile":{"info_cache":{"Default":{"name":"Work","user_name":"me@x.com"}}}}"#
            .write(to: home.appendingPathComponent("\(chrome)/Local State"), atomically: true, encoding: .utf8)
        let items = await ChromeStorageCategory(home: home).scan().items
        XCTAssertEqual(items.map(\.title), ["Work · me@x.com"])
        XCTAssertFalse(items[0].paths.contains { $0.path.contains("IndexedDB") }, "site data is never listed")
    }

    func testLargeOldFilesTickInstallersOnly() async throws {
        try write("Downloads/Setup.dmg", bytes: 30_000_000, age: old)
        try write("Movies/talk.mov", bytes: 210_000_000, age: old)
        try write("Downloads/recent.dmg", bytes: 30_000_000)            // used recently
        try write("Downloads/notes.txt", bytes: 30_000_000, age: old)   // not large, not an installer
        var category = LargeOldFilesCategory(home: home)
        category.largeFileSize = 200_000_000
        let items = await category.scan().items
        XCTAssertEqual(Set(items.map(\.title)), ["Setup.dmg", "talk.mov"])
        XCTAssertEqual(items.first { $0.title == "Setup.dmg" }?.isSelectedByDefault, true)
        XCTAssertEqual(items.first { $0.title == "talk.mov" }?.isSelectedByDefault, false)
    }

    func testDuplicatesNeedIdenticalContentAndKeepThePlainName() async throws {
        try write("Pictures/beach.jpg", bytes: 2_000_000, fill: 7, age: old)
        try write("Downloads/beach (1).jpg", bytes: 2_000_000, fill: 7)
        try write("Downloads/same-size-different.jpg", bytes: 2_000_000, fill: 8)
        let items = await DuplicatesCategory(home: home).scan().items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "beach.jpg")
        XCTAssertEqual(items[0].paths.map(\.lastPathComponent), ["beach (1).jpg"])
    }

    func testCopyNamesAreRecognised() {
        let keep = DuplicatesCategory.copyToKeep([URL(fileURLWithPath: "/x/report copy.pdf"),
                                                  URL(fileURLWithPath: "/x/report 2.pdf"),
                                                  URL(fileURLWithPath: "/x/report.pdf")])
        XCTAssertEqual(keep.lastPathComponent, "report.pdf")
    }
}
