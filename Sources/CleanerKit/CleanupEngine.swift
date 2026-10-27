import AppKit
import Foundation

/// Entry point for the UI: scans every category and cleans selected items.
public struct CleanupEngine: Sendable {
    public let home: URL
    public let categories: [any CleanupCategory]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, settings: CleanerSettings = CleanerSettings()) {
        self.home = home
        self.categories = [
            ProjectBuildsCategory(home: home, staleAfter: TimeInterval(settings.staleDays) * 86400,
                                  customRoots: settings.projectFolders),
            DockerCategory(),
            SimulatorsCategory(home: home),
            XcodeCategory(home: home),
            AndroidCategory(home: home),
            EditorsCategory(home: home),
            ToolchainsCategory(home: home),
            FolderListCategory.developerCaches(home: home),
            AIToolsCategory(home: home),
            LocalModelsCategory(home: home),
            AerialWallpapersCategory(home: home),
            TrashCategory(home: home),
            LargeOldFilesCategory(home: home),
            DuplicatesCategory(home: home),
            HiddenFoldersCategory(home: home),
            FolderListCategory.browserCaches(home: home),
            ChromeStorageCategory(home: home),
            WhatsAppCategory(home: home),
            TelegramCategory(home: home),
        ]
    }

    /// Build folders inside specific folders, e.g. ones picked in Finder. Everything found is ticked,
    /// since the user asked for exactly these folders.
    public static func buildFiles(in folders: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser) async -> [CleanupItem] {
        let category = ProjectBuildsCategory(home: home, staleAfter: 0, customRoots: folders)
        return await category.scan().items
    }

    public init(home: URL, categories: [any CleanupCategory]) {
        self.home = home
        self.categories = categories
    }

    /// Scans all categories in parallel and yields each result as soon as it's ready,
    /// so the UI can fill in while slower categories are still scanning.
    public func scan() -> AsyncStream<CategoryResult> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: CategoryResult.self) { group in
                    for category in categories {
                        group.addTask { await category.scan() }
                    }
                    for await result in group { continuation.yield(result) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Cleans `items`. Quits `appsToQuit` first and reports per-item failures
    /// instead of stopping at the first one.
    public func clean(_ items: [CleanupItem], appsToQuit: [AppIdentity] = [],
                      progress: @escaping @Sendable (CleanProgress) -> Void = { _ in }) async -> CleanReport {
        let home = self.home
        return await Task.detached(priority: .userInitiated) {
            let before = FileSystem.availableCapacity(home: home)
            var failures: [CleanFailure] = []
            for app in appsToQuit where !(await AppControl.quit(app)) {
                failures.append(CleanFailure(itemTitle: app.name, message: "\(app.name) didn't quit, so its items were skipped."))
            }
            let blocked = Set(appsToQuit.filter(AppControl.isRunning).map(\.bundleID))
            var deleted: Int64 = 0, trashed: Int64 = 0
            for (index, item) in items.enumerated() {
                progress(CleanProgress(completedItems: index, totalItems: items.count, currentTitle: item.title))
                if let app = item.owningApp, blocked.contains(app.bundleID) { continue }
                let errors = Cleaner.remove(item, home: home)
                failures += errors.map { CleanFailure(itemTitle: item.title, message: $0) }
                guard errors.count < max(item.paths.count, 1) else { continue }
                if case .moveToTrash = item.method { trashed += item.size } else { deleted += item.size }
            }
            progress(CleanProgress(completedItems: items.count, totalItems: items.count, currentTitle: ""))
            let after = FileSystem.availableCapacity(home: home)
            return CleanReport(deletedBytes: deleted, trashedBytes: trashed,
                               measuredFreedBytes: max(0, after - before), failures: failures)
        }.value
    }
}

/// Performs the removal for one item.
enum Cleaner {
    /// Returns error messages; an empty array means everything succeeded.
    static func remove(_ item: CleanupItem, home: URL) -> [String] {
        switch item.method {
        case .delete:
            return item.paths.flatMap { delete($0) }
        case .moveToTrash:
            return item.paths.compactMap { moveToTrash($0) }
        case .command(let argv):
            let result = Shell.run(argv)
            return result.succeeded ? [] : ["\(argv.joined(separator: " ")) failed: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))"]
        }
    }

    /// Deletes a file or folder. If a folder can't be removed whole (an app has files open),
    /// removes what it can inside it and reports one message for the rest.
    static func delete(_ url: URL) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        do {
            try fm.removeItem(at: url)
            return []
        } catch {
            guard FileSystem.isDirectory(url),
                  let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
                return ["\(url.path.abbreviatingHome): \(error.localizedDescription)"]
            }
            let stuck = children.filter { child in (try? fm.removeItem(at: child)) == nil && fm.fileExists(atPath: child.path) }
            return stuck.isEmpty ? [] : ["\(stuck.count) item\(stuck.count == 1 ? "" : "s") in \(url.path.abbreviatingHome) are in use and were skipped"]
        }
    }

    /// How items are trashed. Tests replace this so they never touch the real Trash.
    nonisolated(unsafe) static var trash: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Moves `url` to the Trash with the system API, which records where it came from so
    /// Finder's "Put Back" works. Folders are recreated empty afterwards so the owning app
    /// finds the structure it expects.
    static func moveToTrash(_ url: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let wasDirectory = FileSystem.isDirectory(url)
        do {
            try trash(url)
            if wasDirectory { try? fm.createDirectory(at: url, withIntermediateDirectories: true) }
            return nil
        } catch {
            return "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

/// Quits apps before their data is cleaned.
public enum AppControl {
    public static func isRunning(_ app: AppIdentity) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Asks the app to quit and waits up to `timeout` seconds. Returns true once it's gone.
    public static func quit(_ app: AppIdentity, timeout: TimeInterval = 20) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isRunning(app) { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return !isRunning(app)
    }
}

/// Full Disk Access is needed to read other apps' data (WhatsApp, Telegram).
public enum Permissions {
    /// Whether this app has Full Disk Access. The TCC database is readable only with it.
    public static var hasFullDiskAccess: Bool {
        FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") != nil
    }

    /// Opens System Settings at Privacy & Security › Full Disk Access.
    @MainActor public static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows the item in Finder.
    @MainActor public static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Turns a selection into a reviewable shell script, for builders who'd rather run it themselves.
public enum ShellScript {
    public static func make(for items: [CleanupItem], appsToQuit: [AppIdentity] = [], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        var lines = ["#!/bin/zsh", "# Generated by MacCleaner on \(ISO8601DateFormatter().string(from: Date()))",
                     "# \(items.count) item\(items.count == 1 ? "" : "s"), about \(FileSystem.format(items.reduce(0) { $0 + $1.size }))",
                     "set -u", ""]
        for app in appsToQuit {
            lines.append("osascript -e 'quit app id \"\(app.bundleID)\"'  # \(app.name)")
        }
        if !appsToQuit.isEmpty { lines.append("") }
        for item in items {
            lines.append("# \(item.title) — \(FileSystem.format(item.size)) — \(item.method.label)")
            switch item.method {
            case .delete:
                lines += item.paths.map { "rm -rf -- \(shellQuote($0.path))" }
            case .moveToTrash:
                // macOS's `trash` command uses the same API as Finder, so Put Back works.
                lines += item.paths.map { "trash \(shellQuote($0.path))" }
            case .command(let argv):
                lines.append(argv.map(shellQuote).joined(separator: " "))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// User choices from the Settings window.
public struct CleanerSettings: Sendable, Equatable {
    /// Folders that contain code projects. nil means the usual places (~/code, ~/Developer, ~/Projects…).
    public var projectFolders: [URL]?
    /// Projects with no commits or edits for this many days are ticked by default.
    public var staleDays: Int

    public init(projectFolders: [URL]? = nil, staleDays: Int = 30) {
        self.projectFolders = projectFolders
        self.staleDays = staleDays
    }

    /// The folders scanned when `projectFolders` is nil and that exist on this Mac.
    public static func defaultProjectFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var seen = Set<String>()
        return ProjectBuildsCategory.roots.map { home.appendingPathComponent($0) }.filter(FileSystem.isDirectory).filter {
            seen.insert((try? $0.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier).map { "\($0)" } ?? $0.path).inserted
        }
    }
}
