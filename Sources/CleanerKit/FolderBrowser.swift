import Foundation

/// Lists folders with their sizes, like System Settings › Storage › File Browser.
public actor FolderBrowser {
    public struct Entry: Identifiable, Sendable, Hashable {
        public var id: URL { url }
        public let url: URL
        public let name: String
        public let isFolder: Bool
        public let modified: Date?
    }

    public let home: URL
    private var sizes: [URL: Int64] = [:]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// The folder's contents, hidden items included, without sizes (those arrive from `sizes(for:)`).
    public nonisolated func entries(in folder: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.lastPathComponent != ".DS_Store" }.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            // Packages (apps, Photos libraries) are shown as single items, like Finder does.
            let isFolder = v?.isDirectory == true && v?.isPackage != true && v?.isSymbolicLink != true
            return Entry(url: url, name: url.lastPathComponent, isFolder: isFolder, modified: v?.contentModificationDate)
        }
    }

    /// Sizes for each entry, yielded as each one is measured. Results are cached for the session.
    public nonisolated func sizes(for entries: [Entry]) -> AsyncStream<(URL, Int64)> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: (URL, Int64).self) { group in
                    var running = 0
                    for entry in entries {
                        if let cached = await self.cachedSize(entry.url) {
                            continuation.yield((entry.url, cached))
                            continue
                        }
                        if running >= 8 { if let done = await group.next() { await self.store(done); continuation.yield(done) }; running -= 1 }
                        group.addTask { (entry.url, FileSystem.allocatedSize(of: entry.url)) }
                        running += 1
                    }
                    for await done in group {
                        await self.store(done)
                        continuation.yield(done)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func cachedSize(_ url: URL) -> Int64? { sizes[url] }
    private func store(_ result: (URL, Int64)) { sizes[result.0] = result.1 }

    /// Forgets cached sizes for a folder and everything above it, after something inside it was removed.
    public func invalidate(_ url: URL) {
        var current = url.standardizedFileURL
        while current.path.count >= home.path.count {
            sizes.removeValue(forKey: current)
            sizes = sizes.filter { !$0.key.path.hasPrefix(url.path + "/") }
            current = current.deletingLastPathComponent()
        }
    }

    /// Whether moving `url` to the Trash is allowed: anything inside the home folder except the home
    /// folder itself, the standard top-level folders, Library, the Trash and credential folders.
    public nonisolated static func canTrash(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardizedFileURL.path, homePath = home.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return false }
        let relative = String(path.dropFirst(homePath.count + 1))
        let protected: Set<String> = ["Library", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
                                      "Public", "Applications", ".Trash", ".ssh", ".gnupg", ".aws", ".kube",
                                      "Library/Keychains", "Library/Preferences", "Library/Application Support",
                                      "Library/Containers", "Library/Group Containers", "Library/Mobile Documents",
                                      "Library/Mail", "Library/Messages", "Library/CloudStorage"]
        return !protected.contains(relative)
    }
}
