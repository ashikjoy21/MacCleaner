import Foundation

/// Offline caches that websites store in Chrome through service workers, per profile,
/// plus Chrome's updater download caches.
struct ChromeStorageCategory: CleanupCategory {
    let id = "chrome-storage"
    let home: URL

    static let app = AppIdentity(name: "Google Chrome", bundleID: "com.google.Chrome")

    var chrome: URL { home.appendingPathComponent("Library/Application Support/Google/Chrome") }

    /// Per-profile folders that are pure caches. Cookies, history, passwords and IndexedDB are not listed.
    static let profileCaches = ["Service Worker/CacheStorage", "Service Worker/ScriptCache", "GPUCache",
                                "DawnGraphiteCache", "DawnWebGPUCache", "Code Cache"]

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .otherApps, name: "Chrome Site Storage",
            summary: "Offline copies that websites cached in Chrome, per profile.",
            explanation: "Web apps (Gmail, Notion, Figma, Slack…) store offline copies of their files in each profile's "
                + "Service Worker/CacheStorage. Deleting it is like clearing a site's cache: you stay signed in and your "
                + "history, passwords, cookies and IndexedDB data are kept; sites download what they need again. "
                + "GoogleUpdater's crx_cache holds update installers. Chrome is quit first.",
            symbol: "globe.badge.chevron.backward", safety: .regenerates, appToQuit: Self.app)

        guard FileSystem.isDirectory(chrome) else { return base.with(status: .unavailable("Chrome isn't installed")) }
        let names = Self.profileNames(localState: chrome.appendingPathComponent("Local State"))
        let profiles = ((try? FileManager.default.contentsOfDirectory(at: chrome, includingPropertiesForKeys: nil)) ?? [])
            .filter { ($0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ")) && FileSystem.isDirectory($0) }

        var items: [CleanupItem] = profiles.compactMap { profile in
            let paths = Self.profileCaches.map { profile.appendingPathComponent($0) }.filter(FileSystem.isDirectory)
            let size = FileSystem.allocatedSize(of: paths)
            guard size > 20_000_000 else { return nil }
            let folder = profile.lastPathComponent
            return CleanupItem(id: "chrome:\(folder)", title: names[folder] ?? folder,
                               subtitle: "\(folder) · service worker and GPU caches", paths: paths, size: size,
                               method: .delete, isSelectedByDefault: true,
                               lastModified: paths.compactMap(FileSystem.modificationDate).max())
        }
        let updater = [home.appendingPathComponent("Library/Application Support/Google/GoogleUpdater/crx_cache"),
                       chrome.appendingPathComponent("component_crx_cache")].filter(FileSystem.isDirectory)
        let updaterSize = FileSystem.allocatedSize(of: updater)
        if updaterSize > 20_000_000 {
            items.append(CleanupItem(id: "chrome:updater", title: "Update downloads",
                                     subtitle: "GoogleUpdater and component installers", paths: updater, size: updaterSize,
                                     method: .delete, isSelectedByDefault: true))
        }
        return base.with(items: items)
    }

    /// Profile folder → the name shown in Chrome's profile menu, from "Local State".
    static func profileNames(localState: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: localState),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [:] }
        var names: [String: String] = [:]
        for (folder, info) in cache {
            let name = (info["name"] as? String) ?? ""
            let user = (info["user_name"] as? String) ?? ""
            names[folder] = (name == user ? [name] : [name, user]).filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return names
    }
}
