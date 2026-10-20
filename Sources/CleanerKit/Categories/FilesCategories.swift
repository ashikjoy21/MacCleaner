import CryptoKit
import Foundation

/// Folders with the user's own files that the Files scans look through.
enum UserFolders {
    static let names = ["Downloads", "Desktop", "Documents", "Movies", "Pictures"]

    /// Regular files under the user folders, skipping packages (apps, Photos libraries) and hidden items.
    static func files(home: URL, in names: [String] = UserFolders.names, minimumSize: Int64) -> [(url: URL, size: Int64, used: Date?)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .contentAccessDateKey, .isPackageKey]
        var result: [(URL, Int64, Date?)] = []
        for name in names {
            let root = home.appendingPathComponent(name)
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                                  errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let size = v.fileSize, Int64(size) >= minimumSize else { continue }
                // "Last used" is the later of the last edit and the last open.
                let used = [v.contentModificationDate, v.contentAccessDate].compactMap { $0 }.max()
                result.append((url, Int64(size), used))
            }
        }
        return result
    }
}

/// Big files and installers in Downloads, Desktop, Documents and Movies that haven't been used for a while.
struct LargeOldFilesCategory: CleanupCategory {
    let id = "large-old-files"
    let home: URL
    var minimumAge: TimeInterval = 90 * 24 * 3600
    var largeFileSize: Int64 = 200_000_000
    var installerSize: Int64 = 20_000_000
    var now = Date()

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso", "apk", "aab", "ipa"]
    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "7z", "rar"]

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .files, name: "Large & Old Files",
            summary: "Big files and installers in Downloads, Desktop, Documents and Movies you haven't opened in 90 days.",
            explanation: "Lists files over 200 MB, and installers or archives (.dmg, .pkg, .xip, .apk, .zip…) over 20 MB, "
                + "that haven't been opened or changed for 90 days. Pictures and Photos libraries are skipped. "
                + "Installers are ticked since the app they installed is already on your Mac; everything else starts "
                + "unticked. Ticked files go to the Trash.",
            symbol: "doc.zipper", safety: .recoverable)

        let cutoff = now.addingTimeInterval(-minimumAge)
        let files = UserFolders.files(home: home, in: ["Downloads", "Desktop", "Documents", "Movies"], minimumSize: installerSize)
        let items: [CleanupItem] = files.compactMap { file in
            let ext = file.url.pathExtension.lowercased()
            let isInstaller = Self.installerExtensions.contains(ext)
            let isArchive = Self.archiveExtensions.contains(ext)
            guard isInstaller || isArchive || file.size >= largeFileSize else { return nil }
            guard let used = file.used, used < cutoff else { return nil }
            let kind = isInstaller ? "Installer" : isArchive ? "Archive" : "Large file"
            var subtitle = kind
            if let rel = FileSystem.relative(used) { subtitle += " · last used \(rel)" }
            return CleanupItem(id: "large:\(file.url.path)", title: file.url.lastPathComponent, subtitle: subtitle,
                               paths: [file.url], size: FileSystem.allocatedSize(of: file.url), method: .moveToTrash,
                               isSelectedByDefault: isInstaller, lastModified: used)
        }
        return base.with(items: items)
    }
}

/// Identical files (same bytes) in the user's folders. One copy of each is kept.
struct DuplicatesCategory: CleanupCategory {
    let id = "duplicates"
    let home: URL
    var minimumSize: Int64 = 1_000_000

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .files, name: "Duplicate Files",
            summary: "Exact copies of the same file in Downloads, Desktop, Documents, Movies and Pictures.",
            explanation: "Files of the same size are compared by a SHA-256 hash of their full contents, so only true copies "
                + "are listed; names don't matter. For each set, the copy with the plainest name and oldest date is kept "
                + "(\"photo.jpg\" over \"photo (1).jpg\" or \"photo 2.jpg\"), and the extra copies go to the Trash. "
                + "Files inside the Photos library are never touched.",
            symbol: "square.on.square", safety: .recoverable)

        let files = UserFolders.files(home: home, minimumSize: minimumSize)
        let groups = Self.duplicateGroups(files.map { ($0.url, $0.size) })
        let items = groups.map { group -> CleanupItem in
            let keep = Self.copyToKeep(group)
            let extras = group.filter { $0 != keep }
            return CleanupItem(id: "dup:\(keep.path)", title: keep.lastPathComponent,
                               subtitle: "\(group.count) copies · keeps \(keep.deletingLastPathComponent().path.abbreviatingHome)",
                               paths: extras, size: FileSystem.allocatedSize(of: extras), method: .moveToTrash,
                               isSelectedByDefault: true, lastModified: FileSystem.modificationDate(of: keep))
        }
        return base.with(items: items)
    }

    /// Groups files whose contents are identical. Sizes are compared first, then a hash of the
    /// first megabyte, then a full hash, so most files are never read in full.
    static func duplicateGroups(_ files: [(URL, Int64)]) -> [[URL]] {
        let bySize = Dictionary(grouping: files, by: \.1).values.filter { $0.count > 1 }
        var groups: [[URL]] = []
        for sameSize in bySize {
            let byHead = Dictionary(grouping: sameSize.map(\.0)) { hash($0, limit: 1 << 20) ?? UUID().uuidString }
            for candidates in byHead.values where candidates.count > 1 {
                let byFull = Dictionary(grouping: candidates) { hash($0, limit: nil) ?? UUID().uuidString }
                groups += byFull.values.filter { $0.count > 1 }
            }
        }
        return groups
    }

    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0, let chunk = try? handle.read(upToCount: min(4 << 20, remaining)), !chunk.isEmpty {
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The copy to keep: no "copy" / "(1)" / " 2" suffix if possible, then the oldest, then the shortest path.
    static func copyToKeep(_ group: [URL]) -> URL {
        func looksLikeCopy(_ url: URL) -> Bool {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name.range(of: #"(\(\d+\)| \d+| copy( \d+)?|-copy)$"#, options: .regularExpression) != nil
        }
        return group.min { a, b in
            if looksLikeCopy(a) != looksLikeCopy(b) { return !looksLikeCopy(a) }
            let da = FileSystem.modificationDate(of: a) ?? .distantFuture, db = FileSystem.modificationDate(of: b) ?? .distantFuture
            if da != db { return da < db }
            return a.path.count < b.path.count
        }!
    }
}
