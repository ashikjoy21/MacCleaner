import Foundation

/// 4K Aerial wallpaper and screen-saver videos macOS downloaded and kept.
struct AerialWallpapersCategory: CleanupCategory {
    let id = "aerial-wallpapers"
    let home: URL
    /// The most recently downloaded videos are kept so the current wallpaper doesn't have to download again.
    var keepNewest = 3

    var aerials: URL { home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials") }

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .system, name: "Aerial Wallpapers",
            summary: "4K wallpaper and screen-saver videos macOS downloaded and kept.",
            explanation: "When you use an Aerial wallpaper or screen saver, especially with shuffle, macOS downloads each "
                + "video (300–700 MB) into com.apple.wallpaper/aerials/videos and keeps it. Deleting them is safe: macOS "
                + "downloads a video again the next time it's shown. The \(keepNewest) most recently downloaded videos start "
                + "unticked so your current wallpaper stays ready.",
            symbol: "photo.on.rectangle.angled", safety: .regenerates)

        let videos = aerials.appendingPathComponent("videos")
        guard FileSystem.isDirectory(videos) else { return base.with(status: .unavailable("No Aerial videos downloaded")) }
        let names = Self.videoNames(manifest: aerials.appendingPathComponent("manifest/entries.json"))
        let files = ((try? FileManager.default.contentsOfDirectory(at: videos, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "mov" }
            .map { (url: $0, date: FileSystem.modificationDate(of: $0) ?? .distantPast) }
            .sorted { $0.date > $1.date }
        let items = files.enumerated().map { index, file in
            let assetID = file.url.deletingPathExtension().lastPathComponent
            return CleanupItem(id: "aerial:\(assetID)", title: names[assetID] ?? "Aerial video",
                               subtitle: index < keepNewest ? "Recently downloaded · kept by default" : file.url.lastPathComponent,
                               paths: [file.url], size: FileSystem.allocatedSize(of: file.url), method: .delete,
                               isSelectedByDefault: index >= keepNewest, lastModified: file.date)
        }
        return base.with(items: items)
    }

    /// Asset ID → readable name ("Tahoe Sunset") from the Aerials manifest.
    static func videoNames(manifest: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else { return [:] }
        var names: [String: String] = [:]
        for asset in assets {
            guard let id = asset["id"] as? String else { continue }
            if let label = asset["accessibilityLabel"] as? String, !label.isEmpty { names[id] = label }
        }
        return names
    }
}

/// What's already in the Trash, including what MacCleaner moved there.
struct TrashCategory: CleanupCategory {
    let id = "trash"
    let home: URL

    var trash: URL { home.appendingPathComponent(".Trash") }

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .system, name: "Trash",
            summary: "Files already in the Trash. They use space until the Trash is emptied.",
            explanation: "Items MacCleaner moves to the Trash only free space once the Trash is emptied. Emptying it "
                + "deletes these items permanently and they can't be put back, so nothing here is ticked by default. "
                + "Check that you don't need anything first (Finder › Go › Trash).",
            symbol: "trash", safety: .review)

        guard FileSystem.exists(trash) else { return base.with(status: .unavailable("No Trash folder")) }
        if FileSystem.isPermissionDenied(trash) { return base.with(status: .needsFullDiskAccess) }
        let entries = ((try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != ".DS_Store" }
        let items = entries.map { entry in
            CleanupItem(id: "trash:\(entry.lastPathComponent)", title: entry.lastPathComponent,
                        subtitle: FileSystem.isDirectory(entry) ? "Folder" : "File", paths: [entry],
                        size: FileSystem.allocatedSize(of: entry), method: .delete, isSelectedByDefault: false,
                        lastModified: FileSystem.modificationDate(of: entry))
        }.filter { $0.size > 0 }
        return base.with(items: items)
    }
}
