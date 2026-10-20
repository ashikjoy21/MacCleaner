import CleanerKit
import Foundation

// Scan-only command-line front end, for checking the engine without the UI.
// Usage: swift run cleanerctl [--items]

let showItems = CommandLine.arguments.contains("--items")
let engine = CleanupEngine()
let disk = DiskUsage.current()
print("Disk: \(FileSystem.format(disk.availableBytes)) free of \(FileSystem.format(disk.totalBytes))\n")

var total: Int64 = 0
for await result in engine.scan() {
    switch result.status {
    case .ready:
        guard !result.items.isEmpty else { print("– \(result.name): nothing found"); continue }
        total += result.defaultSelectedSize
        print("● \(result.name): \(FileSystem.format(result.totalSize)) (\(FileSystem.format(result.defaultSelectedSize)) ticked) [\(result.safety.label)]")
        if showItems {
            for item in result.items.prefix(15) {
                print("    \(item.isSelectedByDefault ? "☑" : "☐") \(FileSystem.format(item.size).padding(toLength: 9, withPad: " ", startingAt: 0)) \(item.title) — \(item.subtitle ?? "")")
                print("        \(item.technicalDescription.replacingOccurrences(of: "\n", with: "\n        "))")
            }
            if result.items.count > 15 { print("    … \(result.items.count - 15) more") }
        }
    case .needsFullDiskAccess:
        print("! \(result.name): needs Full Disk Access")
    case .unavailable(let reason):
        print("– \(result.name): \(reason)")
    }
}
print("\nYou can free up \(FileSystem.format(total)) with the default selection.")
