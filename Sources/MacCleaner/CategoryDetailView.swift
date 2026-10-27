import AppKit
import CleanerKit
import QuickLook
import SwiftUI

struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model
    let category: CategoryResult
    @State private var columns = TableColumnCustomization<CleanupItem>()
    @State private var tableSelection = Set<CleanupItem.ID>()
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    private var isProjects: Bool { category.section == .projects }
    @State private var sortOrder = [KeyPathComparator<CleanupItem>(\.size, order: .reverse)]
    private var selectedItems: [CleanupItem] { category.items.filter { model.selectedItemIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: category.symbol).font(.system(size: 36)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(category.name).font(.largeTitle.weight(.semibold))
                        Text("\(FileSystem.format(category.totalSize)) total · \(FileSystem.format(model.selectedBytes(in: category))) selected")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Text(category.safety.label).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: Capsule())
                }
                GroupBox("What this is") {
                    VStack(alignment: .leading, spacing: 6) { Text(category.summary); Text(category.explanation).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                if let app = category.appToQuit, AppControl.isRunning(app) {
                    Label("\(app.name) will be quit before cleaning.", systemImage: "exclamationmark.circle").foregroundStyle(.secondary).font(.callout)
                }
            }.padding(24)

            if case .needsFullDiskAccess = category.status {
                ContentUnavailableView {
                    Label("Full Disk Access Required", systemImage: "hand.raised")
                } description: {
                    Text("MacCleaner needs Full Disk Access to look at \(category.name)'s files. Relaunch MacCleaner after granting access.")
                } actions: {
                    Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(category.items.sorted(using: sortOrder), selection: $tableSelection, sortOrder: $sortOrder, columnCustomization: $columns) {
                    TableColumn("") { item in
                        Toggle("Select \(item.title)", isOn: Binding(get: { model.selectedItemIDs.contains(item.id) }, set: { _ in model.toggle(item) })).labelsHidden().accessibilityLabel("Select \(item.title)")
                    }.width(28).customizationID("select")
                    TableColumn("Name", value: \.title) { item in VStack(alignment: .leading, spacing: 2) { Text(item.title); if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 3) }.width(min: 150, ideal: 240).customizationID("name")
                    TableColumn("Location") { item in Text(item.displayPath ?? "—").font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle).help(item.displayPath ?? "") }.width(min: 110, ideal: 200).customizationID("location")
                    TableColumn("Branch") { item in Text(item.gitBranch ?? "—").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }.width(min: 80, ideal: 140)
                        .customizationID("branch").defaultVisibility(isProjects ? .visible : .hidden)
                    TableColumn("Last commit", value: \.sortableLastCommit) { item in Text(FileSystem.relative(item.lastCommit) ?? "—").foregroundStyle(.secondary) }.width(min: 80, ideal: 110)
                        .customizationID("lastCommit").defaultVisibility(isProjects ? .visible : .hidden)
                    TableColumn("Last changed") { item in Text(FileSystem.relative(item.lastModified) ?? "—").foregroundStyle(.secondary) }.width(min: 80, ideal: 110)
                        .customizationID("lastChanged").defaultVisibility(isProjects ? .hidden : .visible)
                    TableColumn("How") { item in Text(item.method.label).foregroundStyle(.secondary) }.width(min: 70, ideal: 110).customizationID("how")
                    TableColumn("Size", value: \.size) { item in Text(FileSystem.format(item.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 70, ideal: 85).customizationID("size")
                }
                .contextMenu(forSelectionType: CleanupItem.ID.self) { ids in
                    if let item = category.items.first(where: { ids.contains($0.id) }) {
                        if !item.paths.isEmpty { Button("Quick Look", systemImage: "eye") { showPreview(for: ids) } }
                        if let url = item.paths.first { Button("Show in Finder", systemImage: "folder") { Permissions.reveal(url) } }
                        Button("Copy Command", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.technicalDescription, forType: .string) }
                    }
                } primaryAction: { ids in showPreview(for: ids) }
                .onKeyPress(.space) {
                    if previewURL != nil { previewURL = nil } else { showPreview(for: tableSelection) }
                    return .handled
                }
                .quickLookPreview($previewURL, in: previewURLs)
                .padding(.horizontal, 18)
                DisclosureGroup("Commands") {
                    ScrollView { Text(selectedItems.map(\.technicalDescription).joined(separator: "\n\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                        .frame(maxHeight: 130).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                HStack {
                    Button("Select All") { model.setCategory(category, selected: true) }
                    Button("Select None") { model.setCategory(category, selected: false) }
                    Spacer()
                    Text("\(selectedItems.count) selected · \(FileSystem.format(model.selectedBytes(in: category)))").foregroundStyle(.secondary).monospacedDigit()
                    Button("Clean Up \(category.name)…") { model.requestCleanUp(category: category.id) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.delete, modifiers: [.command])
                        .disabled(selectedItems.isEmpty || model.isScanning || model.isCleaning)
                }.padding(20)
            }
        }
    }

    /// Previews the files of the selected rows with Quick Look; arrow keys move between them.
    private func showPreview(for ids: Set<CleanupItem.ID>) {
        let paths = category.items.filter { ids.contains($0.id) }.flatMap { $0.paths.prefix(200) }
        guard !paths.isEmpty else { return }
        previewURLs = paths.map(QuickLookSupport.previewableURL)
        previewURL = previewURLs.first
    }
}

private extension CleanupItem {
    var sortableLastCommit: Date { lastCommit ?? .distantPast }
}
