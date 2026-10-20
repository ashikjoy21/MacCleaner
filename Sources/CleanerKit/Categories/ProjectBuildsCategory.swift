import Foundation

/// Installed dependencies and build output inside code projects.
struct ProjectBuildsCategory: CleanupCategory {
    let id = "project-builds"
    let home: URL
    /// Projects untouched for this long are ticked by default.
    var staleAfter: TimeInterval = 30 * 24 * 3600
    var maxDepth = 5
    /// Folders to scan instead of the usual ones (~/code, ~/Developer…), from Settings or a Finder request.
    var customRoots: [URL]?

    /// Folder names that are build artifacts, and the files that must sit next to
    /// them to prove they belong to a project (so an unrelated "build" folder is never picked up).
    static let artifacts: [String: Set<String>] = [
        "node_modules": ["package.json"],
        ".next": ["package.json"],
        ".nuxt": ["package.json"],
        ".turbo": ["package.json"],
        ".dart_tool": ["pubspec.yaml"],
        ".build": ["Package.swift"],
        "build": ["package.json", "pubspec.yaml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        ".gradle": ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        "target": ["Cargo.toml"],
    ]

    static let roots = ["code", "Developer", "Projects", "projects", "src", "dev", "Code", "GitHub", "repos"]

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .projects, name: "Project Build Files",
            summary: "Installed packages and build output inside your code projects.",
            explanation: "Folders like node_modules, .next, build and .dart_tool are recreated by running the project's "
                + "install or build command again (npm install, flutter pub get, ./gradlew build…). Your source code is not touched. "
                + "Projects with no commits or file changes in \(Int(staleAfter / 86400)) days are ticked; active projects start unticked.",
            symbol: "folder.badge.gearshape", safety: .review)

        // On a case-insensitive disk ~/code and ~/Code are the same folder, so dedupe by file identity.
        var seenRoots = Set<String>()
        let candidates = customRoots ?? Self.roots.map { home.appendingPathComponent($0) }
        let rootURLs = candidates.filter(FileSystem.isDirectory).filter { url in
            let identity = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier)
                .map { "\($0)" } ?? url.path
            return seenRoots.insert(identity).inserted
        }
        let found = rootURLs.flatMap { findArtifacts(in: $0) }
        let items = await withTaskGroup(of: CleanupItem.self) { group in
            for artifact in found {
                group.addTask { makeItem(for: artifact) }
            }
            var all: [CleanupItem] = []
            for await item in group where item.size > 10_000_000 { all.append(item) } // skip under 10 MB
            return all
        }
        return base.with(items: items)
    }

    /// Walks a root folder looking for artifact folders, without descending into them.
    func findArtifacts(in root: URL) -> [URL] {
        var results: [URL] = []
        func walk(_ dir: URL, depth: Int) {
            guard depth <= maxDepth,
                  let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            else { return }
            let names = Set(entries.map(\.lastPathComponent))
            for entry in entries {
                guard let v = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      v.isDirectory == true, v.isSymbolicLink != true else { continue }
                let name = entry.lastPathComponent
                if let markers = Self.artifacts[name] {
                    if !markers.isDisjoint(with: names) { results.append(entry) }
                    continue // never descend into artifact folders
                }
                if name.hasPrefix(".") || name == "Pods" { continue }
                walk(entry, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return results
    }

    func makeItem(for artifact: URL) -> CleanupItem {
        let project = artifact.deletingLastPathComponent()
        let lastChanged = projectLastModified(project)
        let git = Self.gitInfo(for: project)
        // Active means a recent commit or recent uncommitted edits, whichever is newer.
        let lastActive = [lastChanged, git.lastCommit].compactMap { $0 }.max()
        let stale = lastActive.map { Date().timeIntervalSince($0) > staleAfter } ?? false
        var subtitle = artifact.lastPathComponent
        if let branch = git.branch { subtitle += " · \(branch)" }
        if let rel = FileSystem.relative(git.lastCommit) { subtitle += " · last commit \(rel)" }
        else if let rel = FileSystem.relative(lastChanged) { subtitle += " · changed \(rel)" }
        return CleanupItem(id: "project:\(artifact.path)", title: projectName(project), subtitle: subtitle,
                           paths: [artifact], size: FileSystem.allocatedSize(of: artifact), method: .delete,
                           isSelectedByDefault: stale, lastModified: lastChanged,
                           gitBranch: git.branch, lastCommit: git.lastCommit)
    }

    /// The checked-out branch and latest commit date, or nils when the folder isn't in a git repo.
    static func gitInfo(for project: URL) -> (branch: String?, lastCommit: Date?) {
        let log = Shell.run(["git", "-C", project.path, "log", "-1", "--format=%ct"], timeout: 10)
        guard log.succeeded, let seconds = TimeInterval(log.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return (nil, nil)
        }
        let head = Shell.run(["git", "-C", project.path, "rev-parse", "--abbrev-ref", "HEAD"], timeout: 10)
        let branch = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (head.succeeded && !branch.isEmpty ? branch : nil, Date(timeIntervalSince1970: seconds))
    }

    /// Project name, including the parent folder when the project sits inside another
    /// one (e.g. "abc-dashboard-adapter/client").
    private func projectName(_ project: URL) -> String {
        let parent = project.deletingLastPathComponent()
        if Self.roots.contains(parent.lastPathComponent)
            && parent.deletingLastPathComponent().resolvingSymlinksInPath().path == home.resolvingSymlinksInPath().path {
            return project.lastPathComponent
        }
        return "\(parent.lastPathComponent)/\(project.lastPathComponent)"
    }

    /// Newest modification among the project's top-level entries, ignoring artifact folders.
    private func projectLastModified(_ project: URL) -> Date? {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        return entries.filter { Self.artifacts[$0.lastPathComponent] == nil && $0.lastPathComponent != ".DS_Store" }
            .compactMap(FileSystem.modificationDate).max()
    }
}
