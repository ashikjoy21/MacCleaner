import Foundation

/// File-system helpers. These are synchronous on purpose: callers run them
/// inside detached tasks so the UI never waits on disk I/O.
public enum FileSystem {
    public static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    public static func format(_ bytes: Int64) -> String { byteFormatter.string(fromByteCount: bytes) }

    public static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Bytes allocated on disk for a file or everything under a folder, counted the way `du` does:
    /// symlinks are not followed and a hard-linked file is counted once.
    public static func allocatedSize(of url: URL) -> Int64 {
        var seenLinks = Set<HardLink>()
        return allocatedSize(of: url, seenLinks: &seenLinks)
    }

    /// Same as `allocatedSize(of:)` for several paths, without counting shared hard links twice.
    public static func allocatedSize(of urls: [URL]) -> Int64 {
        var seenLinks = Set<HardLink>()
        return urls.reduce(0) { $0 + allocatedSize(of: $1, seenLinks: &seenLinks) }
    }

    struct HardLink: Hashable { let device: Int32; let inode: UInt64 }

    static func allocatedSize(of url: URL, seenLinks: inout Set<HardLink>) -> Int64 {
        func size(_ path: String) -> Int64 {
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return 0 }
            if st.st_nlink > 1 && !seenLinks.insert(HardLink(device: st.st_dev, inode: st.st_ino)).inserted { return 0 }
            return Int64(st.st_blocks) * 512
        }
        guard isDirectory(url) else { return size(url.path) }
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return 0 }
        let base = url.path
        var total: Int64 = 0
        while let relative = enumerator.nextObject() as? String {
            total += size(base + "/" + relative)
        }
        return total
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// True when macOS refused to list the folder because of privacy protection (TCC).
    public static func isPermissionDenied(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return false
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return true }
            if let posix = error.userInfo[NSUnderlyingErrorKey] as? NSError,
               posix.domain == NSPOSIXErrorDomain, posix.code == Int(EPERM) || posix.code == Int(EACCES) { return true }
            return false
        }
    }

    /// Free space as Finder reports it, including purgeable space.
    public static func availableCapacity(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Int64 {
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                        .volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
    }

    /// "4 months ago" style text.
    public static func relative(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Used and free space on the startup disk, for the usage bar.
public struct DiskUsage: Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    public var usedBytes: Int64 { totalBytes - availableBytes }
    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }

    public static func current(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> DiskUsage {
        let total = (try? home.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity).flatMap { $0 } ?? 0
        return DiskUsage(totalBytes: Int64(total), availableBytes: FileSystem.availableCapacity(home: home))
    }
}
