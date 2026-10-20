import Foundation

/// Homebrew leftovers, unused Node versions and Arduino download staging.
struct ToolchainsCategory: CleanupCategory {
    let id = "toolchains"
    let home: URL

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, name: "Toolchains & Runtimes",
            summary: "Old Homebrew downloads and versions, extra Node versions and toolchain downloads.",
            explanation: "`brew cleanup` removes outdated formula versions and downloads Homebrew no longer needs. "
                + "nvm keeps every Node version you've installed in ~/.nvm/versions/node; versions other than your default "
                + "are listed unticked, since a project may still use them (`nvm install` brings one back). "
                + "Arduino keeps downloaded board packages in Arduino15/staging after installing them.",
            symbol: "wrench.and.screwdriver", safety: .review)

        var items: [CleanupItem] = []
        if let brew = homebrewCleanup() { items.append(brew) }
        items += extraNodeVersions()
        let staging = home.appendingPathComponent("Library/Arduino15/staging")
        if FileSystem.isDirectory(staging) {
            let size = FileSystem.allocatedSize(of: staging)
            if size > 10_000_000 {
                items.append(CleanupItem(id: "toolchains:arduino-staging", title: "Arduino downloads",
                                         subtitle: "Board package archives already installed", paths: [staging], size: size,
                                         method: .delete, isSelectedByDefault: true,
                                         lastModified: FileSystem.modificationDate(of: staging)))
            }
        }
        return base.with(items: items)
    }

    /// Runs `brew cleanup -n` (dry run) and turns its estimate into one item.
    func homebrewCleanup() -> CleanupItem? {
        guard Shell.which("brew") != nil else { return nil }
        let dryRun = Shell.run(["brew", "cleanup", "-n"], timeout: 120)
        guard dryRun.succeeded, let size = Self.parseBrewEstimate(dryRun.output), size > 1_000_000 else { return nil }
        let count = dryRun.output.split(separator: "\n").filter { $0.hasPrefix("Would remove") }.count
        return CleanupItem(id: "toolchains:brew-cleanup", title: "Homebrew cleanup",
                           subtitle: "\(count) outdated download\(count == 1 ? "" : "s") and version\(count == 1 ? "" : "s")",
                           paths: [], size: size, method: .command(["brew", "cleanup"]), isSelectedByDefault: true)
    }

    /// "==> This operation would free approximately 297.2MB of disk space." → bytes (Homebrew uses powers of 1000).
    static func parseBrewEstimate(_ output: String) -> Int64? {
        guard let line = output.split(separator: "\n").last(where: { $0.contains("would free approximately") }),
              let token = line.split(separator: " ").first(where: { $0.first?.isNumber == true }) else { return nil }
        return DockerCategory.parseSize(String(token))
    }

    /// Node versions under ~/.nvm other than the default alias.
    func extraNodeVersions() -> [CleanupItem] {
        let versions = home.appendingPathComponent(".nvm/versions/node")
        let installed = ((try? FileManager.default.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileSystem.isDirectory($0) && $0.lastPathComponent.hasPrefix("v") }
        guard installed.count > 1 else { return [] }
        let alias = (try? String(contentsOf: home.appendingPathComponent(".nvm/alias/default"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keep = Self.defaultNodeVersion(alias: alias, installed: installed.map(\.lastPathComponent))
        return installed.filter { $0.lastPathComponent != keep }.map { dir in
            CleanupItem(id: "toolchains:node:\(dir.lastPathComponent)", title: "Node \(dir.lastPathComponent)",
                        subtitle: "Installed with nvm · default is \(keep ?? "not set")", paths: [dir],
                        size: FileSystem.allocatedSize(of: dir), method: .delete, isSelectedByDefault: false,
                        lastModified: FileSystem.modificationDate(of: dir))
        }
    }

    /// Resolves an nvm alias ("24", "v24.13.0", "node", "lts/*") to the installed version it means.
    /// Returns the newest installed version when the alias can't be matched, so that one is always kept.
    static func defaultNodeVersion(alias: String, installed: [String]) -> String? {
        func parts(_ v: String) -> [Int] { v.drop(while: { $0 == "v" }).split(separator: ".").map { Int($0) ?? 0 } }
        let sorted = installed.sorted { parts($0).lexicographicallyPrecedes(parts($1)) }
        let wanted = alias.hasPrefix("v") ? alias : "v" + alias
        if let exact = sorted.last(where: { $0 == wanted || $0.hasPrefix(wanted + ".") }) { return exact }
        return sorted.last
    }
}
