import Foundation

/// Leftover extension versions and caches for VS Code-based editors.
struct EditorsCategory: CleanupCategory {
    let id = "editors"
    let home: URL

    struct Editor {
        let name: String
        let extensions: String        // relative to home
        let support: String           // relative to home, the app's Application Support folder
    }

    static let editors = [
        Editor(name: "VS Code", extensions: ".vscode/extensions", support: "Library/Application Support/Code"),
        Editor(name: "Cursor", extensions: ".cursor/extensions", support: "Library/Application Support/Cursor"),
        Editor(name: "Windsurf", extensions: ".windsurf/extensions", support: "Library/Application Support/Windsurf"),
        Editor(name: "VS Code Insiders", extensions: ".vscode-insiders/extensions", support: "Library/Application Support/Code - Insiders"),
    ]

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, name: "Code Editors",
            summary: "Old extension versions and caches left by VS Code, Cursor and similar editors.",
            explanation: "When an extension updates, the editor leaves the previous version's folder behind. The list of "
                + "installed extensions is in extensions/extensions.json; folders it doesn't mention are old versions or "
                + "uninstalled extensions. CachedData and CachedExtensionVSIXs are caches the editor rebuilds. "
                + "Settings, keybindings and workspace history are not touched. Quit the editor for a full clean.",
            symbol: "chevron.left.forwardslash.chevron.right", safety: .regenerates)

        var items: [CleanupItem] = []
        for editor in Self.editors {
            items += Self.leftoverExtensions(in: home.appendingPathComponent(editor.extensions), editor: editor.name)
            for cache in ["CachedData", "CachedExtensionVSIXs", "Cache", "Code Cache", "GPUCache"] {
                let url = home.appendingPathComponent(editor.support).appendingPathComponent(cache)
                guard FileSystem.isDirectory(url) else { continue }
                let size = FileSystem.allocatedSize(of: url)
                guard size > 10_000_000 else { continue }
                items.append(CleanupItem(id: "editor:\(editor.name):\(cache)", title: "\(editor.name) · \(cache)",
                                         subtitle: "Cache the editor rebuilds", paths: [url], size: size, method: .delete,
                                         isSelectedByDefault: true, lastModified: FileSystem.modificationDate(of: url)))
            }
        }
        return base.with(items: items)
    }

    /// Extension folders not listed in extensions.json. Returns nothing if the file can't be read,
    /// so an unreadable registry never makes installed extensions look unused.
    static func leftoverExtensions(in folder: URL, editor: String) -> [CleanupItem] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("extensions.json")),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !entries.isEmpty else { return [] }
        var installed = Set<String>()
        for entry in entries {
            if let relative = entry["relativeLocation"] as? String { installed.insert(relative) }
            if let location = entry["location"] as? [String: Any], let path = location["path"] as? String {
                installed.insert(URL(fileURLWithPath: path).lastPathComponent)
            }
        }
        let folders = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileSystem.isDirectory($0) && !$0.lastPathComponent.hasPrefix(".") && !installed.contains($0.lastPathComponent) }
        guard !folders.isEmpty else { return [] }
        return [CleanupItem(id: "editor:\(editor):leftover-extensions", title: "\(editor) · old extension versions",
                            subtitle: "\(folders.count) folder\(folders.count == 1 ? "" : "s") not in extensions.json",
                            paths: folders, size: FileSystem.allocatedSize(of: folders), method: .delete,
                            isSelectedByDefault: true, lastModified: folders.compactMap(FileSystem.modificationDate).max())]
    }
}
