import CleanerKit
import Foundation

// Command-line front end to the same engine as the app.
//
//   cleanerctl                      scan and print a summary
//   cleanerctl [ids…] --items       … with every item (optionally only these categories, e.g. `cleanerctl telegram`)
//   cleanerctl --json               scan and print JSON (for scripts and CI)
//   cleanerctl script [ids…]        print a shell script for the default selection (optionally only these categories)
//   cleanerctl clean [ids…] --yes   clean the default selection (optionally only these categories)

let args = Array(CommandLine.arguments.dropFirst())
let flags = Set(args.filter { $0.hasPrefix("--") })
let positional = args.filter { !$0.hasPrefix("--") }
let commands: Set<String> = ["scan", "script", "clean"]
let command = positional.first.flatMap { commands.contains($0) ? $0 : nil } ?? "scan"
let categoryFilter = Set(positional.filter { !commands.contains($0) })

let engine = CleanupEngine()
var results: [CategoryResult] = []
let quiet = flags.contains("--json") || command == "script"
if !quiet { FileHandle.standardError.write("Scanning…\n".data(using: .utf8)!) }
for await result in engine.scan() where categoryFilter.isEmpty || categoryFilter.contains(result.id) {
    results.append(result)
}
results.sort { ($0.section, $1.totalSize) < ($1.section, $0.totalSize) }
let ready = results.filter { if case .ready = $0.status { return !$0.items.isEmpty } else { return false } }
let defaults = ready.flatMap { $0.items.filter(\.isSelectedByDefault) }
let apps = ready.filter { r in r.items.contains(where: \.isSelectedByDefault) }.compactMap(\.appToQuit)

switch command {
case "script":
    print(ShellScript.make(for: defaults, appsToQuit: apps))

case "clean":
    let total = FileSystem.format(defaults.reduce(0) { $0 + $1.size })
    guard flags.contains("--yes") else {
        print("Would clean \(defaults.count) items (\(total)). Run again with --yes to do it, or `cleanerctl script` to review the commands.")
        exit(0)
    }
    let report = await engine.clean(defaults, appsToQuit: apps) { p in
        if !p.currentTitle.isEmpty { print("[\(p.completedItems + 1)/\(p.totalItems)] \(p.currentTitle)") }
    }
    print("Deleted \(FileSystem.format(report.deletedBytes)), moved \(FileSystem.format(report.trashedBytes)) to the Trash, disk gained \(FileSystem.format(report.measuredFreedBytes)).")
    for failure in report.failures { print("! \(failure.itemTitle): \(failure.message)") }
    exit(report.failures.isEmpty ? 0 : 1)

default:
    if flags.contains("--json") {
        let iso = ISO8601DateFormatter()
        let json: [[String: Any]] = results.map { r in
            var status = "ready"
            if case .needsFullDiskAccess = r.status { status = "needs-full-disk-access" }
            if case .unavailable(let reason) = r.status { status = "unavailable: \(reason)" }
            return ["id": r.id, "section": r.section.title, "name": r.name, "status": status, "safety": r.safety.rawValue,
                    "totalBytes": r.totalSize, "defaultSelectedBytes": r.defaultSelectedSize,
                    "items": r.items.map { i -> [String: Any] in
                        var o: [String: Any] = ["id": i.id, "title": i.title, "bytes": i.size, "method": i.method.label,
                                                "selectedByDefault": i.isSelectedByDefault, "command": i.technicalDescription,
                                                "paths": i.paths.prefix(50).map(\.path), "pathCount": i.paths.count]
                        if let b = i.gitBranch { o["gitBranch"] = b }
                        if let c = i.lastCommit { o["lastCommit"] = iso.string(from: c) }
                        if let m = i.lastModified { o["lastModified"] = iso.string(from: m) }
                        return o
                    }]
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    }
    let disk = DiskUsage.current()
    print("Disk: \(FileSystem.format(disk.availableBytes)) free of \(FileSystem.format(disk.totalBytes))")
    var section: CategorySection?
    for r in results {
        if r.section != section { section = r.section; print("\n\(r.section.title.uppercased())") }
        switch r.status {
        case .ready:
            guard !r.items.isEmpty else { print("  – \(r.name) [\(r.id)]: nothing found"); continue }
            print("  ● \(r.name) [\(r.id)]: \(FileSystem.format(r.totalSize)) (\(FileSystem.format(r.defaultSelectedSize)) ticked)")
            guard flags.contains("--items") else { continue }
            for i in r.items.prefix(12) {
                print("      \(i.isSelectedByDefault ? "☑" : "☐") \(FileSystem.format(i.size).padding(toLength: 9, withPad: " ", startingAt: 0)) \(i.title) — \(i.subtitle ?? "")")
            }
            if r.items.count > 12 { print("      … \(r.items.count - 12) more") }
        case .needsFullDiskAccess: print("  ! \(r.name) [\(r.id)]: needs Full Disk Access")
        case .unavailable(let reason): print("  – \(r.name) [\(r.id)]: \(reason)")
        }
    }
    print("\nYou can free up \(FileSystem.format(defaults.reduce(0) { $0 + $1.size })) with the default selection.")
}
