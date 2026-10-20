import AppIntents
import CleanerKit
import Foundation

// App Intents: actions for Shortcuts, Spotlight and Siri. The App Shortcuts at the bottom
// appear automatically, with no setup by the user.

/// Categories that can be cleaned from Shortcuts. Other apps' data (WhatsApp, Telegram) is left
/// to the app, where the user can see what they're removing.
enum CleanableCategory: String, AppEnum {
    case projectBuilds = "project-builds"
    case docker
    case simulators
    case xcode
    case android
    case editors
    case toolchains
    case developerCaches = "developer-caches"
    case browserCaches = "browser-caches"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cleanup Category"
    static let caseDisplayRepresentations: [CleanableCategory: DisplayRepresentation] = [
        .projectBuilds: DisplayRepresentation(title: "Project Build Files", subtitle: "Stale node_modules, build, .next…", image: .init(systemName: "folder.badge.gearshape")),
        .docker: DisplayRepresentation(title: "Docker", subtitle: "Unused images, containers and build cache", image: .init(systemName: "shippingbox")),
        .simulators: DisplayRepresentation(title: "Simulators", subtitle: "Simulators for missing runtimes", image: .init(systemName: "iphone")),
        .xcode: DisplayRepresentation(title: "Xcode", subtitle: "DerivedData and device support", image: .init(systemName: "hammer.circle")),
        .android: DisplayRepresentation(title: "Android & Gradle", subtitle: "Unused system images and old Gradle", image: .init(systemName: "apps.iphone")),
        .editors: DisplayRepresentation(title: "Code Editors", subtitle: "Old extensions and editor caches", image: .init(systemName: "chevron.left.forwardslash.chevron.right")),
        .toolchains: DisplayRepresentation(title: "Toolchains & Runtimes", subtitle: "Homebrew cleanup and downloads", image: .init(systemName: "wrench.and.screwdriver")),
        .developerCaches: DisplayRepresentation(title: "Developer Caches", subtitle: "npm, pnpm, Gradle, pip, Go…", image: .init(systemName: "hammer")),
        .browserCaches: DisplayRepresentation(title: "Browser Caches", subtitle: "Chrome, Brave, Edge, Firefox, Arc", image: .init(systemName: "globe")),
    ]
}

/// Scans the given categories (or all) with the user's settings.
private func scan(_ ids: Set<String>? = nil) async -> [CategoryResult] {
    let engine = CleanupEngine(settings: SettingsStore.current)
    let categories = engine.categories.filter { ids?.contains($0.id) ?? true }
    return await withTaskGroup(of: CategoryResult.self) { group in
        for category in categories { group.addTask { await category.scan() } }
        var results: [CategoryResult] = []
        for await result in group { results.append(result) }
        return results
    }
}

struct FreeableSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Can I Free Up?"
    static let description = IntentDescription(
        "Scans your Mac and reports how much space MacCleaner's default selection would free. Nothing is removed.",
        categoryName: "Scan")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let results = await scan()
        let total = results.reduce(Int64(0)) { $0 + $1.defaultSelectedSize }
        let biggest = results.max { $0.defaultSelectedSize < $1.defaultSelectedSize }
        var text = "You can free up \(FileSystem.format(total))."
        if let biggest, biggest.defaultSelectedSize > 0 {
            text += " The most is in \(biggest.name) (\(FileSystem.format(biggest.defaultSelectedSize)))."
        }
        text += " \(FileSystem.format(DiskUsage.current().availableBytes)) is available now."
        return .result(value: Int(total), dialog: IntentDialog(stringLiteral: text))
    }
}

struct CleanCategoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Up Category"
    static let description = IntentDescription(
        "Cleans the items MacCleaner ticks by default in one category, after asking you to confirm.",
        categoryName: "Clean")

    @Parameter(title: "Category")
    var category: CleanableCategory

    static var parameterSummary: some ParameterSummary { Summary("Clean up \(\.$category)") }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let result = await scan([category.rawValue]).first else {
            return .result(value: 0, dialog: "MacCleaner couldn't scan that category.")
        }
        let items = result.items.filter(\.isSelectedByDefault)
        guard !items.isEmpty else {
            return .result(value: 0, dialog: IntentDialog(stringLiteral: "Nothing in \(result.name) needs cleaning right now."))
        }
        let size = FileSystem.format(items.reduce(0) { $0 + $1.size })
        try await requestConfirmation(
            result: .result(dialog: IntentDialog(stringLiteral: "Clean \(size) from \(result.name)? \(items.count) item\(items.count == 1 ? "" : "s") will be \(items[0].method.label.lowercased())."))
        )
        let report = await CleanupEngine(settings: SettingsStore.current)
            .clean(items, appsToQuit: result.appToQuit.map { [$0] } ?? [])
        var text = "Freed \(FileSystem.format(report.deletedBytes)) from \(result.name)."
        if report.trashedBytes > 0 { text += " \(FileSystem.format(report.trashedBytes)) went to the Trash." }
        if !report.failures.isEmpty { text += " \(report.failures.count) item\(report.failures.count == 1 ? "" : "s") couldn't be cleaned." }
        return .result(value: Int(report.deletedBytes + report.trashedBytes), dialog: IntentDialog(stringLiteral: text))
    }
}

struct OpenMacCleanerIntent: AppIntent {
    static let title: LocalizedStringResource = "Open MacCleaner"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

struct MacCleanerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FreeableSpaceIntent(),
                    phrases: ["How much can \(.applicationName) free up",
                              "Check disk space with \(.applicationName)",
                              "Scan my Mac with \(.applicationName)"],
                    shortTitle: "Freeable Space", systemImageName: "internaldrive")
        AppShortcut(intent: CleanCategoryIntent(),
                    phrases: ["Clean \(\.$category) with \(.applicationName)",
                              "Clean up with \(.applicationName)"],
                    shortTitle: "Clean Up", systemImageName: "sparkles")
        AppShortcut(intent: OpenMacCleanerIntent(),
                    phrases: ["Open \(.applicationName)"],
                    shortTitle: "Open MacCleaner", systemImageName: "macwindow")
    }
}
