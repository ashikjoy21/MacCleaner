import Foundation

/// Unused Docker images, stopped containers, unused volumes and build cache.
struct DockerCategory: CleanupCategory {
    let id = "docker"

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, name: "Docker", summary: "Images, containers, volumes and build cache that nothing is using.",
            explanation: "Uses Docker's own prune commands, so only resources no container is using are removed. "
                + "Images download again the next time you run or build something that needs them. "
                + "Unused volumes hold data from containers that no longer exist; that data is lost when they're pruned.",
            symbol: "shippingbox", safety: .review)

        guard Shell.which("docker") != nil else { return base.with(status: .unavailable("Docker isn't installed")) }
        let result = Shell.run(["docker", "system", "df", "--format", "{{json .}}"], timeout: 60)
        guard result.succeeded else { return base.with(status: .unavailable("Docker isn't running")) }
        return base.with(items: Self.items(fromDockerDF: result.output))
    }

    /// Parses `docker system df --format '{{json .}}'`, one JSON object per line.
    static func items(fromDockerDF output: String) -> [CleanupItem] {
        output.split(separator: "\n").compactMap { line -> CleanupItem? in
            guard let data = line.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let type = row["Type"], let reclaimable = row["Reclaimable"] else { return nil }
            let size = parseSize(reclaimable)
            guard size > 0 else { return nil }
            let total = row["TotalCount"] ?? "?", active = row["Active"] ?? "?"
            switch type {
            case "Images":
                // `docker image prune -a` only removes images no container uses. When every image is in use
                // Docker still reports space as reclaimable, but pruning frees nothing.
                guard total != active else { return nil }
                return CleanupItem(id: "docker:images", title: "Unused images", subtitle: "\(total) images, \(active) in use",
                                   paths: [], size: size, method: .command(["docker", "image", "prune", "-a", "-f"]),
                                   isSelectedByDefault: true)
            case "Containers":
                return CleanupItem(id: "docker:containers", title: "Stopped containers", subtitle: "\(total) containers, \(active) running",
                                   paths: [], size: size, method: .command(["docker", "container", "prune", "-f"]),
                                   isSelectedByDefault: true)
            case "Local Volumes":
                return CleanupItem(id: "docker:volumes", title: "Unused volumes", subtitle: "\(total) volumes, \(active) in use · data is lost",
                                   paths: [], size: size, method: .command(["docker", "volume", "prune", "-a", "-f"]),
                                   isSelectedByDefault: false)
            case "Build Cache":
                return CleanupItem(id: "docker:build-cache", title: "Build cache", subtitle: "Layers cached from earlier builds",
                                   paths: [], size: size, method: .command(["docker", "builder", "prune", "-a", "-f"]),
                                   isSelectedByDefault: true)
            default:
                return nil
            }
        }
    }

    /// Parses Docker's human sizes ("17.05GB (51%)", "883.7MB", "0B") into bytes. Docker uses powers of 1000.
    static func parseSize(_ text: String) -> Int64 {
        let token = text.split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, factor) in units where token.hasSuffix(suffix) {
            return Int64((Double(token.dropLast(suffix.count)) ?? 0) * factor)
        }
        return 0
    }
}
