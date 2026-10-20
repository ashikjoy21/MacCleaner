import Foundation

/// A known folder that is safe to delete, with a line explaining what it is.
struct KnownFolder: Sendable {
    let name: String
    let relativePath: String
    let note: String
}

/// A category made of a fixed list of cache folders, each deleted outright.
struct FolderListCategory: CleanupCategory {
    let id: String
    let name: String
    let summary: String
    let explanation: String
    let symbol: String
    let home: URL
    let folders: [KnownFolder]

    func scan() async -> CategoryResult {
        let base = CategoryResult(id: id, name: name, summary: summary, explanation: explanation,
                                  symbol: symbol, safety: .regenerates)
        let items = await withTaskGroup(of: CleanupItem?.self) { group in
            for folder in folders {
                group.addTask {
                    let url = home.appendingPathComponent(folder.relativePath)
                    guard FileSystem.isDirectory(url) else { return nil }
                    let size = FileSystem.allocatedSize(of: url)
                    guard size > 1_000_000 else { return nil } // skip anything under 1 MB
                    return CleanupItem(id: "\(id):\(folder.relativePath)", title: folder.name, subtitle: folder.note,
                                       paths: [url], size: size, method: .delete, isSelectedByDefault: true,
                                       lastModified: FileSystem.modificationDate(of: url))
                }
            }
            var found: [CleanupItem] = []
            for await item in group { if let item { found.append(item) } }
            return found
        }
        return base.with(items: items)
    }
}

extension FolderListCategory {
    static func developerCaches(home: URL) -> FolderListCategory {
        FolderListCategory(
            id: "developer-caches", name: "Developer Caches",
            summary: "Packages that build tools downloaded and kept for reuse.",
            explanation: "Package managers keep a copy of every package they download so the next install is faster. "
                + "Deleting these folders is safe: the next install or build downloads what it needs again. "
                + "Projects keep their own installed packages.",
            symbol: "hammer", home: home,
            folders: [
                KnownFolder(name: "npm", relativePath: ".npm/_cacache", note: "npm's download cache"),
                KnownFolder(name: "pnpm cache", relativePath: "Library/Caches/pnpm", note: "pnpm's metadata and download cache"),
                KnownFolder(name: "pnpm store", relativePath: "Library/pnpm/store", note: "pnpm's shared package store"),
                KnownFolder(name: "Yarn", relativePath: "Library/Caches/Yarn", note: "Yarn's download cache"),
                KnownFolder(name: "Bun", relativePath: ".bun/install/cache", note: "Bun's package cache"),
                KnownFolder(name: "Gradle", relativePath: ".gradle/caches", note: "Downloaded dependencies and build caches for Android/Java"),
                KnownFolder(name: "pip", relativePath: "Library/Caches/pip", note: "Python package downloads"),
                KnownFolder(name: "Go build cache", relativePath: "Library/Caches/go-build", note: "Compiled Go packages"),
                KnownFolder(name: "Swift Package Manager", relativePath: "Library/Caches/org.swift.swiftpm", note: "Swift package downloads"),
                KnownFolder(name: "CocoaPods", relativePath: "Library/Caches/CocoaPods", note: "CocoaPods spec repo and pod downloads"),
                KnownFolder(name: "Homebrew", relativePath: "Library/Caches/Homebrew", note: "Downloaded Homebrew bottles and installers"),
            ])
    }

    static func browserCaches(home: URL) -> FolderListCategory {
        FolderListCategory(
            id: "browser-caches", name: "Browser Caches",
            summary: "Copies of web pages, images and scripts browsers keep to load sites faster.",
            explanation: "Only the cache folders are removed. History, passwords, bookmarks and sign-ins live elsewhere "
                + "and are not touched. Sites may load a little slower the first time afterwards. "
                + "Files a running browser is using are skipped; quit the browser for a full clean.",
            symbol: "globe", home: home,
            folders: [
                KnownFolder(name: "Google Chrome", relativePath: "Library/Caches/Google/Chrome", note: "Chrome's page and media cache"),
                KnownFolder(name: "Brave", relativePath: "Library/Caches/BraveSoftware", note: "Brave's page and media cache"),
                KnownFolder(name: "Microsoft Edge", relativePath: "Library/Caches/Microsoft Edge", note: "Edge's page and media cache"),
                KnownFolder(name: "Firefox", relativePath: "Library/Caches/Firefox", note: "Firefox's page and media cache"),
                KnownFolder(name: "Arc", relativePath: "Library/Caches/Arc", note: "Arc's page and media cache"),
            ])
    }
}
