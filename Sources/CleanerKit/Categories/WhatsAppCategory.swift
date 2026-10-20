import Foundation
import SQLite3

/// Media files WhatsApp keeps on disk that no message, thumbnail or profile
/// picture in its database refers to any more.
struct WhatsAppCategory: CleanupCategory {
    let id = "whatsapp"
    let home: URL
    /// Leftovers newer than this are left alone in case WhatsApp hasn't saved its database yet.
    var minimumAge: TimeInterval = 30 * 24 * 3600
    var now = Date()

    static let app = AppIdentity(name: "WhatsApp", bundleID: "net.whatsapp.WhatsApp")

    var container: URL { home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared") }

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .otherApps, name: "WhatsApp Leftover Media",
            summary: "Photos, videos and voice notes that no chat refers to any more.",
            explanation: "WhatsApp leaves media files on disk after messages are deleted or chat history is re-synced. "
                + "This compares every file in Message/Media with the paths stored in WhatsApp's database (ChatStorage.sqlite: "
                + "media, thumbnails, group and profile pictures) and lists only files nothing points to, older than 30 days. "
                + "They're moved to the Trash, keeping their folder layout, so you can put them back. "
                + "WhatsApp is quit first so its database is fully saved.",
            symbol: "message", safety: .recoverable, appToQuit: Self.app)

        guard FileSystem.isDirectory(container) else { return base.with(status: .unavailable("WhatsApp isn't installed")) }
        if FileSystem.isPermissionDenied(container) { return base.with(status: .needsFullDiskAccess) }

        let database = container.appendingPathComponent("ChatStorage.sqlite")
        guard let db = WhatsAppDatabase(url: database) else {
            return base.with(status: .unavailable("Couldn't read WhatsApp's database"))
        }
        let referenced = db.referencedMediaPaths()
        // An empty set would make every file look unused. Treat it as a failure, never as "delete all".
        guard !referenced.isEmpty else { return base.with(status: .unavailable("WhatsApp's database has no media references")) }
        let chatNames = db.chatNames()

        let media = container.appendingPathComponent("Message/Media")
        let leftovers = Self.unreferencedFiles(in: media, referenced: referenced, olderThan: now.addingTimeInterval(-minimumAge))
        let folder = "WhatsApp leftover media \(Self.dateStamp(now))"
        let byChat = Dictionary(grouping: leftovers) { $0.relativePath.split(separator: "/").first.map(String.init) ?? "" }
        let items = byChat.map { chatID, files in
            CleanupItem(id: "whatsapp:\(chatID)", title: Self.displayName(chatID: chatID, names: chatNames),
                        subtitle: "\(files.count.formatted()) file\(files.count == 1 ? "" : "s") · \(chatID)",
                        paths: files.map(\.url), size: files.reduce(0) { $0 + $1.size },
                        method: .moveToTrash(folder: folder, base: media), isSelectedByDefault: true,
                        lastModified: files.compactMap(\.modified).max())
        }
        return base.with(items: items)
    }

    struct MediaFile {
        let url: URL
        let relativePath: String
        let size: Int64
        let modified: Date?
    }

    /// Files under `media` whose relative path isn't in `referenced` and that haven't changed since `cutoff`.
    static func unreferencedFiles(in media: URL, referenced: Set<String>, olderThan cutoff: Date) -> [MediaFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: media, includingPropertiesForKeys: keys, options: [],
                                                              errorHandler: { _, _ in true }) else { return [] }
        let prefix = media.standardizedFileURL.path + "/"
        var files: [MediaFile] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent != ".DS_Store",
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            guard !referenced.contains(relative) else { continue }
            if let modified = v.contentModificationDate, modified > cutoff { continue }
            files.append(MediaFile(url: url, relativePath: relative, size: Int64(v.totalFileAllocatedSize ?? 0),
                                   modified: v.contentModificationDate))
        }
        return files
    }

    static func displayName(chatID: String, names: [String: String]) -> String {
        if let name = names[chatID]?.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\u{202A}\u{202C}"))),
           !name.isEmpty { return name }
        if chatID.hasSuffix(".status") { return "Status updates" }
        if chatID.hasSuffix("@s.whatsapp.net"), let number = chatID.split(separator: "@").first { return "+\(number)" }
        return "Unknown chat"
    }

    static func dateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// Read-only access to WhatsApp's ChatStorage.sqlite.
final class WhatsAppDatabase {
    private var db: OpaquePointer?

    init?(url: URL) {
        let uri = "file:\(url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 5000)
    }

    deinit { sqlite3_close(db) }

    /// Every value of every column whose name contains "PATH", normalised to a path
    /// relative to Message/Media. Discovering columns instead of hard-coding them means
    /// a new kind of reference in a future WhatsApp version is still respected.
    func referencedMediaPaths() -> Set<String> {
        var paths = Set<String>()
        let columns = rows("""
            SELECT m.name, p.name FROM sqlite_master m JOIN pragma_table_info(m.name) p
            WHERE m.type = 'table' AND p.name LIKE '%PATH%'
            """)
        for row in columns where row.count == 2 {
            let table = row[0].replacingOccurrences(of: "\"", with: ""), column = row[1].replacingOccurrences(of: "\"", with: "")
            for value in rows("SELECT \"\(column)\" FROM \"\(table)\" WHERE \"\(column)\" IS NOT NULL") {
                if let path = value.first, let normalized = Self.normalize(path) { paths.insert(normalized) }
            }
        }
        return paths
    }

    /// Chat folder ID (e.g. "1234@lid") → chat or contact name.
    func chatNames() -> [String: String] {
        var names: [String: String] = [:]
        for row in rows("SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION WHERE ZCONTACTJID IS NOT NULL AND ZPARTNERNAME IS NOT NULL")
        where row.count == 2 { names[row[0]] = row[1] }
        return names
    }

    /// Paths are stored as "Media/<chat>/a/b/file.jpg", sometimes absolute. Returns "<chat>/a/b/file.jpg".
    static func normalize(_ stored: String) -> String? {
        if let range = stored.range(of: "Message/Media/") { return String(stored[range.upperBound...]) }
        if stored.hasPrefix("Media/") { return String(stored.dropFirst("Media/".count)) }
        if stored.hasPrefix("/Media/") { return String(stored.dropFirst("/Media/".count)) }
        return stored.contains("/") ? stored : nil
    }

    private func rows(_ sql: String) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = sqlite3_column_count(statement)
            result.append((0..<count).map { i in
                sqlite3_column_text(statement, i).map { String(cString: $0) } ?? ""
            })
        }
        return result
    }
}
