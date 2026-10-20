import Foundation
import XCTest
@testable import CleanerKit

final class BuilderCategoriesTests: XCTestCase {
    var home: URL!
    let old: TimeInterval = 60 * 24 * 3600

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("BuilderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    @discardableResult
    func write(_ relative: String, _ text: String = String(repeating: "x", count: 4096), age: TimeInterval = 0) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if age > 0 { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path) }
        return url
    }

    func git(_ dir: URL, _ args: String...) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        p.environment = ["GIT_AUTHOR_DATE": "2020-01-01T00:00:00", "GIT_COMMITTER_DATE": "2020-01-01T00:00:00",
                         "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
                         "HOME": home.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: Projects

    func testProjectUsesGitBranchAndLastCommit() throws {
        let project = home.appendingPathComponent("code/api")
        try write("code/api/package.json", age: old)
        try write("code/api/node_modules/a.js")
        git(project, "init", "-q", "-b", "main")
        git(project, "add", "package.json")
        git(project, "commit", "-q", "-m", "init")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-old)], ofItemAtPath: project.appendingPathComponent(".git").path)

        let item = ProjectBuildsCategory(home: home).makeItem(for: project.appendingPathComponent("node_modules"))
        XCTAssertEqual(item.gitBranch, "main")
        XCTAssertEqual(item.lastCommit.map { Calendar(identifier: .gregorian).component(.year, from: $0) }, 2020)
        XCTAssertTrue(item.isSelectedByDefault, "old commit and old files → stale")
    }

    func testRecentEditsKeepAProjectActiveDespiteOldCommits() throws {
        let project = home.appendingPathComponent("code/web")
        try write("code/web/package.json", age: old)
        try write("code/web/node_modules/a.js")
        git(project, "init", "-q", "-b", "main")
        git(project, "add", "package.json")
        git(project, "commit", "-q", "-m", "init")
        try write("code/web/src/new.ts") // uncommitted work today
        XCTAssertFalse(ProjectBuildsCategory(home: home).makeItem(for: project.appendingPathComponent("node_modules")).isSelectedByDefault)
    }

    // MARK: Android

    func testSystemImagesInUseByAnAVDAreKept() throws {
        try write(".android/avd/Pixel.avd/config.ini", "hw.ramSize=2048\nimage.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\n")
        try write("Library/Android/sdk/system-images/android-35/google_apis/arm64-v8a/system.img")
        try write("Library/Android/sdk/system-images/android-33/default/arm64-v8a/system.img")
        let items = AndroidCategory(home: home).unusedSystemImages()
        XCTAssertEqual(items.map(\.title), ["android-33 · default · arm64-v8a"])
    }

    func testOnlyOlderGradleDistributionsAreListed() throws {
        for d in ["gradle-8.12-bin", "gradle-9.3.1-all", "gradle-9.10.0-bin"] { try write(".gradle/wrapper/dists/\(d)/x/gradle.zip") }
        let titles = Set(AndroidCategory(home: home).oldGradleDistributions().map(\.title))
        XCTAssertEqual(titles, ["gradle-8.12-bin", "gradle-9.3.1-all"]) // 9.10 is newer than 9.3
    }

    // MARK: Editors

    func testEditorLeftoversAreFoldersMissingFromExtensionsJSON() throws {
        try write(".vscode/extensions/extensions.json", #"[{"identifier":{"id":"a.b"},"relativeLocation":"a.b-2.0.0"}]"#)
        try write(".vscode/extensions/a.b-2.0.0/package.json")
        try write(".vscode/extensions/a.b-1.0.0/package.json")
        let items = EditorsCategory.leftoverExtensions(in: home.appendingPathComponent(".vscode/extensions"), editor: "VS Code")
        XCTAssertEqual(items.first?.paths.map(\.lastPathComponent), ["a.b-1.0.0"])
    }

    func testUnreadableExtensionRegistryListsNothing() throws {
        try write(".vscode/extensions/a.b-1.0.0/package.json")
        XCTAssertTrue(EditorsCategory.leftoverExtensions(in: home.appendingPathComponent(".vscode/extensions"), editor: "VS Code").isEmpty)
    }

    // MARK: Toolchains

    func testNodeDefaultResolution() {
        let installed = ["v18.20.0", "v20.11.1", "v24.13.0"]
        XCTAssertEqual(ToolchainsCategory.defaultNodeVersion(alias: "20", installed: installed), "v20.11.1")
        XCTAssertEqual(ToolchainsCategory.defaultNodeVersion(alias: "v18.20.0", installed: installed), "v18.20.0")
        XCTAssertEqual(ToolchainsCategory.defaultNodeVersion(alias: "lts/*", installed: installed), "v24.13.0")
    }

    func testBrewEstimateParsing() {
        XCTAssertEqual(ToolchainsCategory.parseBrewEstimate("Would remove: x\n==> This operation would free approximately 297.2MB of disk space."), 297_200_000)
        XCTAssertNil(ToolchainsCategory.parseBrewEstimate("nothing"))
    }

    func testSimulatorRuntimeName() {
        XCTAssertEqual(SimulatorsCategory.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-26-5"), "iOS 26.5")
    }

    // MARK: AI tools

    func testAIHistoryListsOnlyOldTranscriptsAndNothingIsTicked() async throws {
        try write(".claude/projects/p/old.jsonl", String(repeating: "x", count: 2_000_000), age: old)
        try write(".claude/projects/p/new.jsonl", String(repeating: "x", count: 2_000_000))
        try write(".claude/settings.json", age: old)
        let result = await AIToolsCategory(home: home).scan()
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.paths.map(\.lastPathComponent), ["old.jsonl"])
        XCTAssertEqual(result.items.first?.isSelectedByDefault, false)
    }

    // MARK: Shell script

    func testShellScriptQuotesPathsAndPreservesLayout() {
        let items = [
            CleanupItem(id: "1", title: "Cache", paths: [URL(fileURLWithPath: "/Users/me/My Cache")], size: 10, method: .delete, isSelectedByDefault: true),
            CleanupItem(id: "2", title: "Media", paths: [URL(fileURLWithPath: "/m/Media/chat/a.jpg")], size: 5,
                        method: .moveToTrash(folder: "Left overs", base: URL(fileURLWithPath: "/m/Media")), isSelectedByDefault: true),
            CleanupItem(id: "3", title: "Images", paths: [], size: 1, method: .command(["docker", "image", "prune", "-a", "-f"]), isSelectedByDefault: true),
        ]
        let script = ShellScript.make(for: items, home: URL(fileURLWithPath: "/Users/me"))
        XCTAssertTrue(script.contains("rm -rf -- '/Users/me/My Cache'"))
        XCTAssertTrue(script.contains("mv -n -- /m/Media/chat/a.jpg '/Users/me/.Trash/Left overs/chat/a.jpg'"))
        XCTAssertTrue(script.contains("\ndocker image prune -a -f\n"))
    }
}
