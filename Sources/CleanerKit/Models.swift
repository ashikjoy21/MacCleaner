import Foundation

/// How safe a category is to clean, shown to the user as a badge.
public enum Safety: String, Sendable, CaseIterable {
    /// Pure cache. The owning tool rebuilds or re-downloads it on demand.
    case regenerates
    /// Personal data that goes to the Trash, so the user can put it back.
    case recoverable
    /// Worth a look before cleaning. Items start unticked unless clearly stale.
    case review

    public var label: String {
        switch self {
        case .regenerates: "Rebuilds automatically"
        case .recoverable: "Moved to Trash"
        case .review: "Review first"
        }
    }
}

/// What happens to an item when it is cleaned.
public enum RemovalMethod: Sendable, Hashable {
    /// Removed permanently. Only used for data its owner regenerates.
    case delete
    /// Moved into `~/.Trash/<folder>/`, keeping each file's path relative to `base`
    /// so the original layout can be restored by dragging it back.
    case moveToTrash(folder: String, base: URL)
    /// Runs a command, e.g. `docker image prune -a -f`.
    case command([String])

    public var label: String {
        switch self {
        case .delete: "Deleted"
        case .moveToTrash: "Moved to Trash"
        case .command: "Runs a command"
        }
    }

    /// A shell-style description of exactly what will run, for the detail view.
    public func technicalDescription(for paths: [URL]) -> String {
        switch self {
        case .delete:
            return paths.prefix(3).map { "rm -rf \(shellQuote($0.path.abbreviatingHome))" }.joined(separator: "\n")
                + (paths.count > 3 ? "\n… and \(paths.count - 3) more" : "")
        case .moveToTrash(let folder, _):
            return "mv <\(paths.count) item\(paths.count == 1 ? "" : "s")> ~/.Trash/\(folder)/"
        case .command(let argv):
            return argv.map(shellQuote).joined(separator: " ")
        }
    }
}

/// An app that must be quit before its data can be cleaned.
public struct AppIdentity: Sendable, Hashable {
    public let name: String
    public let bundleID: String
    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

/// One row the user can tick: a cache folder, a project's node_modules,
/// one chat's leftover WhatsApp media, a Docker prune step…
public struct CleanupItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    /// Short secondary line, e.g. "3,412 files · last used 4 months ago".
    public let subtitle: String?
    /// Files or folders this item removes. Empty for command items.
    public let paths: [URL]
    /// Bytes on disk. For command items, the tool's own estimate.
    public let size: Int64
    public let method: RemovalMethod
    public let isSelectedByDefault: Bool
    public let lastModified: Date?

    public init(id: String, title: String, subtitle: String? = nil, paths: [URL], size: Int64,
                method: RemovalMethod, isSelectedByDefault: Bool, lastModified: Date? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.paths = paths
        self.size = size
        self.method = method
        self.isSelectedByDefault = isSelectedByDefault
        self.lastModified = lastModified
    }

    /// The path to show in the UI, with the home folder shortened to `~`.
    public var displayPath: String? {
        guard let first = paths.first else { return nil }
        return paths.count == 1 ? first.path.abbreviatingHome : first.deletingLastPathComponent().path.abbreviatingHome
    }

    public var technicalDescription: String { method.technicalDescription(for: paths) }
}

public enum CategoryStatus: Sendable, Hashable {
    case ready
    /// macOS blocked reading the folder. The user must grant Full Disk Access.
    case needsFullDiskAccess
    /// The tool isn't installed or running, or nothing was found. Hidden from the main list.
    case unavailable(String)
}

/// The result of scanning one category.
public struct CategoryResult: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// One plain sentence: what this is.
    public let summary: String
    /// Technical detail: what exactly is removed and how it comes back.
    public let explanation: String
    /// SF Symbol name.
    public let symbol: String
    public let safety: Safety
    public let appToQuit: AppIdentity?
    public let items: [CleanupItem]
    public let status: CategoryStatus

    public init(id: String, name: String, summary: String, explanation: String, symbol: String, safety: Safety,
                appToQuit: AppIdentity? = nil, items: [CleanupItem] = [], status: CategoryStatus = .ready) {
        self.id = id
        self.name = name
        self.summary = summary
        self.explanation = explanation
        self.symbol = symbol
        self.safety = safety
        self.appToQuit = appToQuit
        self.items = items.sorted { $0.size > $1.size }
        self.status = status
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var defaultSelectedSize: Int64 { items.filter(\.isSelectedByDefault).reduce(0) { $0 + $1.size } }

    /// Whether the main list should show this category at all.
    public var isVisible: Bool {
        switch status {
        case .ready: !items.isEmpty
        case .needsFullDiskAccess: true
        case .unavailable: false
        }
    }

    func with(items: [CleanupItem]) -> CategoryResult {
        CategoryResult(id: id, name: name, summary: summary, explanation: explanation, symbol: symbol,
                       safety: safety, appToQuit: appToQuit, items: items, status: status)
    }

    func with(status: CategoryStatus) -> CategoryResult {
        CategoryResult(id: id, name: name, summary: summary, explanation: explanation, symbol: symbol,
                       safety: safety, appToQuit: appToQuit, items: items, status: status)
    }
}

/// A source of cleanable items. Each category scans independently.
public protocol CleanupCategory: Sendable {
    var id: String { get }
    func scan() async -> CategoryResult
}

/// Progress while cleaning, for a progress bar.
public struct CleanProgress: Sendable {
    public let completedItems: Int
    public let totalItems: Int
    public let currentTitle: String
    public var fraction: Double { totalItems == 0 ? 1 : Double(completedItems) / Double(totalItems) }
}

public struct CleanFailure: Sendable, Identifiable {
    public let id = UUID()
    public let itemTitle: String
    public let message: String
}

public struct CleanReport: Sendable {
    /// Sum of the sizes of items that were deleted or pruned.
    public let deletedBytes: Int64
    /// Sum of the sizes of items moved to the Trash. Freed only once the Trash is emptied.
    public let trashedBytes: Int64
    /// Change in the disk's available space, measured before and after.
    public let measuredFreedBytes: Int64
    public let failures: [CleanFailure]
}

func shellQuote(_ s: String) -> String {
    if s.hasPrefix("~/") { return "~/" + shellQuote(String(s.dropFirst(2))) } // keep ~ outside quotes so it still expands
    return s.contains(where: { " '\"$()&;|<>*?".contains($0) }) ? "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" : s
}

extension String {
    var abbreviatingHome: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
