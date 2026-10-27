import Foundation

/// Models downloaded by local AI tools: Ollama, Hugging Face and LM Studio.
struct LocalModelsCategory: CleanupCategory {
    let id = "local-models"
    let home: URL

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .aiTools, name: "Local AI Models",
            summary: "Language and image models downloaded by Ollama, Hugging Face and LM Studio.",
            explanation: "Local models are often 5–40 GB each. Ollama models are removed with `ollama rm <model>`, which "
                + "also frees layers no other model shares; Hugging Face and LM Studio models are folders that are deleted. "
                + "Any model can be downloaded again (`ollama pull`, or the first time a script loads it). Nothing is ticked "
                + "by default.",
            symbol: "cpu", safety: .review)

        var items = ollamaModels()
        items += huggingFaceModels()
        items += lmStudioModels()
        return base.with(items: items)
    }

    /// Parses `ollama list`: NAME, ID, SIZE ("9.5 GB"), MODIFIED.
    func ollamaModels() -> [CleanupItem] {
        guard Shell.which("ollama") != nil else { return [] }
        let list = Shell.run(["ollama", "list"], timeout: 30)
        guard list.succeeded else { return [] }
        return Self.parseOllamaList(list.output).map { model in
            CleanupItem(id: "ollama:\(model.name)", title: model.name, subtitle: "Ollama · \(model.modified)",
                        paths: [], size: model.size, method: .command(["ollama", "rm", model.name]), isSelectedByDefault: false)
        }
    }

    static func parseOllamaList(_ output: String) -> [(name: String, size: Int64, modified: String)] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 4 else { return nil }
            let size = DockerCategory.parseSize(columns[2] + columns[3])  // "9.5" + "GB"
            return (columns[0], size, columns.dropFirst(4).joined(separator: " "))
        }
    }

    /// ~/.cache/huggingface/hub/models--org--name folders.
    func huggingFaceModels() -> [CleanupItem] {
        let hub = home.appendingPathComponent(".cache/huggingface/hub")
        let folders = ((try? FileManager.default.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("models--") || $0.lastPathComponent.hasPrefix("datasets--") }
        return folders.compactMap { folder in
            let size = FileSystem.allocatedSize(of: folder)
            guard size > 50_000_000 else { return nil }
            let parts = folder.lastPathComponent.components(separatedBy: "--")
            let name = parts.dropFirst().joined(separator: "/")
            return CleanupItem(id: "hf:\(folder.lastPathComponent)", title: name,
                               subtitle: "Hugging Face \(parts.first == "datasets" ? "dataset" : "model")", paths: [folder],
                               size: size, method: .delete, isSelectedByDefault: false,
                               lastModified: FileSystem.modificationDate(of: folder))
        }
    }

    /// LM Studio keeps models as <publisher>/<model> folders.
    func lmStudioModels() -> [CleanupItem] {
        let roots = [".lmstudio/models", ".cache/lm-studio/models"].map { home.appendingPathComponent($0) }
        var items: [CleanupItem] = []
        for root in roots {
            for publisher in subfolders(root) {
                for model in subfolders(publisher) {
                    let size = FileSystem.allocatedSize(of: model)
                    guard size > 50_000_000 else { continue }
                    items.append(CleanupItem(id: "lmstudio:\(model.path)",
                                             title: "\(publisher.lastPathComponent)/\(model.lastPathComponent)",
                                             subtitle: "LM Studio model", paths: [model], size: size, method: .delete,
                                             isSelectedByDefault: false, lastModified: FileSystem.modificationDate(of: model)))
                }
            }
        }
        return items
    }

    private func subfolders(_ url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter(FileSystem.isDirectory)
    }
}

/// Hidden folders in the home folder that developer tools create (~/.gradle, ~/.gemini, ~/.rustup…).
struct HiddenFoldersCategory: CleanupCategory {
    let id = "hidden-folders"
    let home: URL
    var minimumSize: Int64 = 100_000_000

    /// Never listed: credentials, shell and system state, and folders other categories handle with care.
    static let excluded: Set<String> = [".Trash", ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".config", ".docker",
                                        ".zsh_sessions", ".ollama", ".claude", ".password-store", ".netrc",
                                        // Installed command-line tools, not data: removing these uninstalls them.
                                        ".local/bin", ".local/share/claude", ".local/share/uv/tools", ".local/pipx"]

    /// What each folder is, shown under its name.
    static let descriptions: [String: String] = [
        ".gemini": "Gemini CLI and Antigravity: conversation history, extensions and temporary files",
        ".antigravity": "Google Antigravity: extensions and editor data",
        ".antigravity-ide": "Google Antigravity IDE: extensions and editor data",
        ".trae": "Trae IDE: extensions and editor data",
        ".cursor": "Cursor: installed extensions",
        ".vscode": "VS Code: installed extensions",
        ".windsurf": "Windsurf: installed extensions",
        ".codex": "Codex CLI: sessions, packages and caches",
        ".rustup": "Rust toolchains installed by rustup (`rustup toolchain list`)",
        ".cargo": "Rust: downloaded crates and installed binaries",
        ".nvm": "Node.js versions installed by nvm",
        ".npm": "npm: download cache and global packages",
        ".bun": "Bun: package cache and installed binaries",
        ".gradle": "Gradle: dependency caches and downloaded distributions",
        ".m2": "Maven: downloaded Java dependencies",
        ".android": "Android: emulators (AVDs) and SDK settings",
        ".pub-cache": "Dart and Flutter: downloaded packages",
        ".dartServer": "Dart analysis server cache",
        ".pyenv": "Python versions installed by pyenv",
        ".conda": "Conda environments and packages",
        ".rbenv": "Ruby versions installed by rbenv",
        ".gem": "Ruby gems",
        ".deno": "Deno: module cache",
        ".expo": "Expo: tools and caches",
        ".bundle": "Ruby Bundler cache",
        ".swiftpm": "Swift Package Manager: caches and configuration",
        ".cocoapods": "CocoaPods: spec repositories",
        ".vagrant.d": "Vagrant boxes",
        ".minikube": "Minikube: cluster images",
        ".colima": "Colima: Docker virtual machine disk",
        ".orbstack": "OrbStack: Linux machines and Docker data",
        ".local": "Tools installed per user (pipx, uv, CLIs) and their data",
        ".cache/huggingface": "Hugging Face models and datasets (also listed under Local AI Models)",
        ".cache/pip": "pip download cache",
        ".cache/uv": "uv package cache",
        ".cache/puppeteer": "Browsers downloaded by Puppeteer",
        ".cache/ms-playwright": "Browsers downloaded by Playwright",
        ".cache/node-gyp": "Node.js headers for native modules",
        ".cache/prisma": "Prisma engines",
        ".cache/lm-studio": "LM Studio models and runtime",
        ".cache/selenium": "Drivers downloaded by Selenium",
        ".cache/go-build": "Go build cache",
        ".cache/pre-commit": "pre-commit hook environments",
        ".cache/codex-runtimes": "Codex: downloaded runtimes, fetched again when needed",
        ".cache/whisper": "Whisper speech models",
        ".cache/torch": "PyTorch model downloads",
    ]

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, section: .files, name: "Hidden Tool Folders",
            summary: "Hidden folders in your home folder that developer tools and AI apps create.",
            explanation: "Every hidden folder in your home folder over 100 MB, largest first. Most belong to a tool you "
                + "installed (Gradle, rustup, Gemini CLI, Antigravity, Trae…) and are recreated by that tool, but some "
                + "hold its settings or history, so nothing is ticked: read the description and tick what you no longer "
                + "use. Ticked folders go to the Trash. Credentials (.ssh, .gnupg, .aws, .kube) are never listed. "
                + "Use the File Browser to look inside a folder first.",
            symbol: "eye.slash", safety: .review)

        var candidates: [URL] = []
        let topLevel = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        for url in topLevel where url.lastPathComponent.hasPrefix(".") && FileSystem.isDirectory(url) {
            let name = url.lastPathComponent
            guard !Self.excluded.contains(name) else { continue }
            if name == ".cache" {
                candidates += ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                    .filter(FileSystem.isDirectory)
            } else if name == ".local" {
                let share = url.appendingPathComponent("share")
                candidates += ((try? FileManager.default.contentsOfDirectory(at: share, includingPropertiesForKeys: nil)) ?? [])
                    .filter(FileSystem.isDirectory)
                candidates += ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                    .filter { FileSystem.isDirectory($0) && $0.lastPathComponent != "share" }
            } else {
                candidates.append(url)
            }
        }
        let homePath = home.resolvingSymlinksInPath().path
        func relative(_ url: URL) -> String { String(url.resolvingSymlinksInPath().path.dropFirst(homePath.count + 1)) }
        candidates.removeAll { Self.excluded.contains(relative($0)) }

        let items = await withTaskGroup(of: CleanupItem?.self) { group in
            for folder in candidates {
                group.addTask {
                    let size = FileSystem.allocatedSize(of: folder)
                    guard size >= minimumSize else { return nil }
                    let name = relative(folder)
                    return CleanupItem(id: "hidden:\(name)", title: "~/\(name)",
                                       subtitle: Self.descriptions[name] ?? "Created by an app or command-line tool",
                                       paths: [folder], size: size, method: .moveToTrash, isSelectedByDefault: false,
                                       lastModified: FileSystem.modificationDate(of: folder))
                }
            }
            var all: [CleanupItem] = []
            for await item in group { if let item { all.append(item) } }
            return all
        }
        return base.with(items: items)
    }
}
