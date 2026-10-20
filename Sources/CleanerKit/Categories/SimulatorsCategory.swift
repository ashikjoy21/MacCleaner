import Foundation

/// iOS, watchOS, tvOS and visionOS simulators, one row per device.
struct SimulatorsCategory: CleanupCategory {
    let id = "simulators"
    let home: URL

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, name: "Simulators",
            summary: "Apps, data and caches stored inside each Xcode simulator.",
            explanation: "Each simulator keeps its installed apps and data in ~/Library/Developer/CoreSimulator/Devices/<UDID>. "
                + "Working simulators are erased with `xcrun simctl erase`, which resets them to a clean state but keeps the device. "
                + "Simulators for runtimes that are no longer installed can't be launched, so they're deleted with `xcrun simctl delete`. "
                + "Running simulators are skipped.",
            symbol: "iphone", safety: .review)

        guard Shell.which("xcrun") != nil else { return base.with(status: .unavailable("Xcode isn't installed")) }
        let result = Shell.run(["xcrun", "simctl", "list", "devices", "-j"], timeout: 60)
        guard result.succeeded, let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else {
            return base.with(status: .unavailable("Couldn't list simulators"))
        }
        let devicesFolder = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        var items: [CleanupItem] = []
        for (runtime, devices) in runtimes {
            for device in devices {
                guard let udid = device["udid"] as? String, let name = device["name"] as? String,
                      (device["state"] as? String) != "Booted" else { continue }
                let folder = devicesFolder.appendingPathComponent(udid)
                let size = FileSystem.allocatedSize(of: folder)
                let available = device["isAvailable"] as? Bool ?? true
                guard size > 50_000_000 || !available else { continue }
                let os = Self.runtimeName(runtime)
                items.append(CleanupItem(
                    id: "simulator:\(udid)", title: "\(name) (\(os))",
                    subtitle: available ? "Erase contents and settings" : "Runtime no longer installed · delete",
                    paths: [folder], size: size,
                    method: .command(["xcrun", "simctl", available ? "erase" : "delete", udid]),
                    isSelectedByDefault: !available, lastModified: FileSystem.modificationDate(of: folder)))
            }
        }
        return base.with(items: items)
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" → "iOS 26.5"
    static func runtimeName(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        guard let dash = last.firstIndex(of: "-") else { return last }
        return last[..<dash] + " " + last[last.index(after: dash)...].replacingOccurrences(of: "-", with: ".")
    }
}
