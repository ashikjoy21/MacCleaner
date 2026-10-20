import Foundation

/// Telegram's downloaded media cache, per signed-in account.
struct TelegramCategory: CleanupCategory {
    let id = "telegram"
    let home: URL

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
            explanation: "Telegram keeps chats in the cloud and caches downloaded media in postbox/media. "
                + "This is the same data Telegram's own Clear Cache removes; media downloads again when you open it. "
                + "Media from secret chats isn't stored in the cloud, so the cache is moved to the Trash rather than deleted. "
                + "Telegram is quit first.",
            symbol: "paperplane", safety: .review, appToQuit: Self.app)

        let existing = containers.filter(FileSystem.isDirectory)
        guard !existing.isEmpty else { return base.with(status: .unavailable("Telegram isn't installed")) }
        if existing.contains(where: FileSystem.isPermissionDenied) { return base.with(status: .needsFullDiskAccess) }

        let folder = "Telegram media cache \(WhatsAppCategory.dateStamp(Date()))"
        var items: [CleanupItem] = []
        for container in existing {
            let accounts = (try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? []
            for (index, account) in accounts.filter({ $0.lastPathComponent.hasPrefix("account-") }).enumerated() {
                let media = account.appendingPathComponent("postbox/media")
                guard FileSystem.isDirectory(media) else { continue }
                let size = FileSystem.allocatedSize(of: media)
                guard size > 1_000_000 else { continue }
                items.append(CleanupItem(id: "telegram:\(account.lastPathComponent)",
                                         title: accounts.count > 1 ? "Account \(index + 1) media" : "Cached media",
                                         subtitle: "postbox/media", paths: [media], size: size,
                                         method: .moveToTrash(folder: folder, base: container),
                                         isSelectedByDefault: false, lastModified: FileSystem.modificationDate(of: media)))
            }
        }
        return base.with(items: items)
    }
}
