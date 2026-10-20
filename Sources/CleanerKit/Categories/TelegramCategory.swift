import Foundation

/// Telegram's downloaded media cache, split by kind, with large files listed one by one.
struct TelegramCategory: CleanupCategory {
    let id = "telegram"
    let home: URL
    /// Files at least this big get their own row so the user can see exactly what they are.
    var largeFileThreshold: Int64 = 300_000_000

    static let app = AppIdentity(name: "Telegram", bundleID: "ru.keepcoder.Telegram")

    /// The Mac App Store build and the direct-download build keep data in different places.
    var containers: [URL] {
        [home.appendingPathComponent("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/appstore"),
         home.appendingPathComponent("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable")]
    }

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .otherApps, name: "Telegram Media Cache",
            summary: "Photos, videos and files Telegram downloaded while you scrolled.",
            explanation: "Telegram keeps chats in the cloud and caches downloaded media in postbox/media. Telegram doesn't "
                + "record which chat a cached file came from outside its encrypted database, so files are grouped by what "
                + "they are (read from each file's header), and every file over 300 MB is listed on its own; use Show in "
                + "Finder to check one. This is the same data Telegram's Clear Cache removes, and media downloads again when "
                + "you open it. Secret-chat media isn't in the cloud, so files go to the Trash rather than being deleted. "
                + "Telegram is quit first.",
            symbol: "paperplane", safety: .review, appToQuit: Self.app)

        let existing = containers.filter(FileSystem.isDirectory)
        guard !existing.isEmpty else { return base.with(status: .unavailable("Telegram isn't installed")) }
        if existing.contains(where: FileSystem.isPermissionDenied) { return base.with(status: .needsFullDiskAccess) }

        let folder = "Telegram media cache \(WhatsAppCategory.dateStamp(Date()))"
        var items: [CleanupItem] = []
        for container in existing {
            let accounts = ((try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("account-") }
            for (index, account) in accounts.enumerated() {
                let media = account.appendingPathComponent("postbox/media")
                guard FileSystem.isDirectory(media) else { continue }
                let prefix = accounts.count > 1 ? "Account \(index + 1) · " : ""
                items += Self.items(in: media, idPrefix: "telegram:\(account.lastPathComponent)", titlePrefix: prefix,
                                    largeFileThreshold: largeFileThreshold,
                                    method: .moveToTrash(folder: folder, base: container))
            }
        }
        return base.with(items: items)
    }

    enum Kind: String, CaseIterable {
        case video = "Videos", photo = "Photos", audio = "Voice messages & audio", document = "Documents & files",
             profile = "Profile pictures", partial = "Unfinished downloads", appCache = "Thumbnails & app cache"
    }

    /// Groups the files in one account's media folder into rows.
    static func items(in media: URL, idPrefix: String, titlePrefix: String, largeFileThreshold: Int64,
                      method: RemovalMethod) -> [CleanupItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: media.path) else { return [] }
        var all: [String: URL] = [:]
        while let relative = enumerator.nextObject() as? String {
            let url = media.appendingPathComponent(relative)
            if !FileSystem.isDirectory(url) { all[relative] = url }
        }

        var groups: [Kind: [URL]] = [:]
        var large: [(name: String, paths: [URL], kind: Kind, format: String)] = []
        for (relative, url) in all {
            let name = url.lastPathComponent
            if relative.contains("/") { groups[.appCache, default: []].append(url); continue }
            if name.hasSuffix("_partial") {
                // A finished download keeps a hard-linked "_partial" twin; it's handled with the finished file.
                if all[String(name.dropLast("_partial".count))] != nil { continue }
                groups[.partial, default: []].append(url)
                continue
            }
            if name.hasPrefix("telegram-peer-photo") { groups[.profile, default: []].append(url); continue }
            let (kind, format) = classify(url)
            var paths = [url]
            let twin = media.appendingPathComponent(name + "_partial")
            if all[twin.lastPathComponent] != nil { paths.append(twin) }
            if FileSystem.allocatedSize(of: paths) >= largeFileThreshold {
                large.append((name, paths, kind, format))
            } else {
                groups[kind, default: []] += paths
            }
        }

        var items: [CleanupItem] = large.map { file in
            CleanupItem(id: "\(idPrefix):file:\(file.name)", title: "\(titlePrefix)\(file.format) \(singular(file.kind))",
                        subtitle: file.name, paths: file.paths, size: FileSystem.allocatedSize(of: file.paths),
                        method: method, isSelectedByDefault: false,
                        lastModified: FileSystem.modificationDate(of: file.paths[0]))
        }
        for kind in Kind.allCases {
            guard let paths = groups[kind], !paths.isEmpty else { continue }
            let size = FileSystem.allocatedSize(of: paths)
            guard size > 1_000_000 else { continue }
            items.append(CleanupItem(id: "\(idPrefix):\(kind)", title: "\(titlePrefix)\(kind.rawValue)",
                                     subtitle: "\(paths.count.formatted()) file\(paths.count == 1 ? "" : "s")",
                                     paths: paths, size: size, method: method, isSelectedByDefault: false,
                                     lastModified: paths.compactMap(FileSystem.modificationDate).max()))
        }
        return items
    }

    private static func singular(_ kind: Kind) -> String {
        switch kind {
        case .video: "video"
        case .photo: "photo"
        case .audio: "audio file"
        default: "file"
        }
    }

    /// Identifies a file from its first bytes. Telegram's cache files have no extensions.
    static func classify(_ url: URL) -> (Kind, String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (.document, "Unknown") }
        defer { try? handle.close() }
        let b = [UInt8](handle.readData(ofLength: 16))
        func starts(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            b.count >= offset + bytes.count && Array(b[offset..<offset + bytes.count]) == bytes
        }
        if starts([0x1A, 0x45, 0xDF, 0xA3]) { return (.video, "MKV") }
        if starts(Array("ftyp".utf8), at: 4) {
            let brand = b.count >= 12 ? String(decoding: b[8..<12], as: UTF8.self) : ""
            if brand.hasPrefix("qt") { return (.video, "MOV") }
            if brand.hasPrefix("M4A") { return (.audio, "M4A") }
            if brand.hasPrefix("heic") || brand.hasPrefix("mif1") { return (.photo, "HEIC") }
            return (.video, "MP4")
        }
        if starts([0xFF, 0xD8, 0xFF]) { return (.photo, "JPEG") }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return (.photo, "PNG") }
        if starts(Array("GIF8".utf8)) { return (.photo, "GIF") }
        if starts(Array("RIFF".utf8)) && starts(Array("WEBP".utf8), at: 8) { return (.photo, "WebP") }
        if starts(Array("OggS".utf8)) { return (.audio, "Ogg") }
        if starts(Array("ID3".utf8)) || starts([0xFF, 0xFB]) { return (.audio, "MP3") }
        if starts(Array("%PDF".utf8)) { return (.document, "PDF") }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return (.document, "ZIP") }
        return (.document, "Other")
    }
}
