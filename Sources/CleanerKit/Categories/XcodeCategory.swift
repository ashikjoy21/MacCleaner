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
                + "Simulators are listed separately under Simulators.",
            symbol: "hammer.circle", safety: .regenerates)

        let folders = await FolderListCategory(id: id, name: "", summary: "", explanation: "", symbol: "", home: home, folders: [
            KnownFolder(name: "DerivedData", relativePath: "Library/Developer/Xcode/DerivedData", note: "Build products and indexes"),
            KnownFolder(name: "iOS Device Support", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", note: "Debug symbols from connected iPhones and iPads"),
            KnownFolder(name: "watchOS Device Support", relativePath: "Library/Developer/Xcode/watchOS DeviceSupport", note: "Debug symbols from connected Apple Watches"),
            KnownFolder(name: "SwiftUI Previews", relativePath: "Library/Developer/Xcode/UserData/Previews", note: "Simulator data for SwiftUI previews"),
            KnownFolder(name: "Simulator caches", relativePath: "Library/Developer/CoreSimulator/Caches", note: "Shared simulator runtime caches"),
        ]).scan().items

        return base.with(items: folders)
    }

}
