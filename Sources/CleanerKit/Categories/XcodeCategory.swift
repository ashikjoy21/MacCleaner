import Foundation

/// Xcode build products, device support files and unavailable simulators.
struct XcodeCategory: CleanupCategory {
    let id = "xcode"
    let home: URL

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, name: "Xcode", summary: "Build products and support files Xcode recreates as needed.",
            explanation: "DerivedData holds intermediate build files and indexes; Xcode rebuilds them on the next build. "
                + "Device Support holds debug symbols copied from devices you've connected; Xcode copies them again the next time. "
                + "Unavailable simulators belong to iOS versions no longer installed and can't be launched anyway.",
            symbol: "hammer.circle", safety: .regenerates)

        let folders = await FolderListCategory(id: id, name: "", summary: "", explanation: "", symbol: "", home: home, folders: [
            KnownFolder(name: "DerivedData", relativePath: "Library/Developer/Xcode/DerivedData", note: "Build products and indexes"),
            KnownFolder(name: "iOS Device Support", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", note: "Debug symbols from connected iPhones and iPads"),
            KnownFolder(name: "watchOS Device Support", relativePath: "Library/Developer/Xcode/watchOS DeviceSupport", note: "Debug symbols from connected Apple Watches"),
            KnownFolder(name: "SwiftUI Previews", relativePath: "Library/Developer/Xcode/UserData/Previews", note: "Simulator data for SwiftUI previews"),
            KnownFolder(name: "Simulator caches", relativePath: "Library/Developer/CoreSimulator/Caches", note: "Shared simulator runtime caches"),
        ]).scan().items

        var items = folders
        if let simulators = unavailableSimulators() { items.append(simulators) }
        return base.with(items: items)
    }

    /// One item that runs `xcrun simctl delete unavailable`, sized from those simulators' folders.
    private func unavailableSimulators() -> CleanupItem? {
        guard Shell.which("xcrun") != nil else { return nil }
        let result = Shell.run(["xcrun", "simctl", "list", "devices", "unavailable", "-j"], timeout: 60)
        guard result.succeeded, let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else { return nil }
        let udids = runtimes.values.flatMap { $0 }.compactMap { $0["udid"] as? String }
        guard !udids.isEmpty else { return nil }
        let devices = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        let paths = udids.map { devices.appendingPathComponent($0) }
        let size = FileSystem.allocatedSize(of: paths)
        return CleanupItem(id: "xcode:unavailable-simulators", title: "Unavailable simulators",
                           subtitle: "\(udids.count) simulator\(udids.count == 1 ? "" : "s") for runtimes that are no longer installed",
                           paths: [], size: size, method: .command(["xcrun", "simctl", "delete", "unavailable"]),
                           isSelectedByDefault: true)
    }
}
