import Foundation

/// Old conversation transcripts and logs kept by AI coding tools.
struct AIToolsCategory: CleanupCategory {
    let id = "ai-tools"
    let home: URL
    var minimumAge: TimeInterval = 30 * 24 * 3600
    var now = Date()

    struct Source {
        let name: String
        let folder: String       // relative to home
        let fileExtensions: Set<String>
        let note: String
    }

    static let sources = [
        Source(name: "Codex sessions", folder: ".codex/sessions", fileExtensions: ["jsonl"], note: "Codex CLI conversation transcripts"),
        Source(name: "Codex logs", folder: ".codex/log", fileExtensions: ["log", "jsonl", "txt"], note: "Codex CLI logs"),
        Source(name: "Claude Code transcripts", folder: ".claude/projects", fileExtensions: ["jsonl"], note: "Claude Code conversation transcripts"),
    ]

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .aiTools, name: "AI Coding History",
            summary: "Old conversation transcripts and logs from Codex and Claude Code.",
            explanation: "Coding agents save every session as a transcript so you can resume it later. Files older than "
                + "30 days are listed; resuming one of those sessions won't be possible once the Trash is emptied. "
                + "They're moved to the Trash (Put Back restores them), nothing here is ticked by default, and "
                + "settings, memory and installed plugins are never touched.",
            symbol: "sparkles", safety: .recoverable)

        let cutoff = now.addingTimeInterval(-minimumAge)
        var items: [CleanupItem] = []
        for source in Self.sources {
            let root = home.appendingPathComponent(source.folder)
            guard FileSystem.isDirectory(root) else { continue }
            let files = Self.files(in: root, extensions: source.fileExtensions, olderThan: cutoff)
            guard !files.isEmpty else { continue }
            let size = FileSystem.allocatedSize(of: files)
            guard size > 1_000_000 else { continue }
            items.append(CleanupItem(id: "ai:\(source.folder)", title: source.name,
                                     subtitle: "\(files.count.formatted()) files older than 30 days · \(source.note)",
                                     paths: files, size: size,
                                     method: .moveToTrash,
                                     isSelectedByDefault: false, lastModified: files.compactMap(FileSystem.modificationDate).max()))
        }
        return base.with(items: items)
    }

    static func files(in root: URL, extensions: Set<String>, olderThan cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                              options: [], errorHandler: { _, _ in true }) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension) {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  v.isRegularFile == true, let modified = v.contentModificationDate, modified < cutoff else { continue }
            result.append(url)
        }
        return result
    }
}
