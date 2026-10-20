import AppKit
import CleanerKit
import SwiftUI

struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model
    let category: CategoryResult
    @State private var columns = TableColumnCustomization<CleanupItem>()
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
                Table(category.items.sorted(using: sortOrder), sortOrder: $sortOrder, columnCustomization: $columns) {
                    TableColumn("") { item in
                        Toggle("Select \(item.title)", isOn: Binding(get: { model.selectedItemIDs.contains(item.id) }, set: { _ in model.toggle(item) })).labelsHidden().accessibilityLabel("Select \(item.title)")
                    }.width(36).customizationID("select")
                    TableColumn("Name", value: \.title) { item in VStack(alignment: .leading, spacing: 2) { Text(item.title); if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 3) }.width(min: 180).customizationID("name")
                    TableColumn("Location") { item in Text(item.displayPath ?? "—").font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle).help(item.displayPath ?? "") }.width(min: 180).customizationID("location")
                    TableColumn("Branch") { item in Text(item.gitBranch ?? "—").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }.width(min: 100)
                        .customizationID("branch").defaultVisibility(isProjects ? .visible : .hidden)
                    TableColumn("Last commit", value: \.sortableLastCommit) { item in Text(FileSystem.relative(item.lastCommit) ?? "—").foregroundStyle(.secondary) }.width(min: 105)
                        .customizationID("lastCommit").defaultVisibility(isProjects ? .visible : .hidden)
                    TableColumn("Last changed") { item in Text(FileSystem.relative(item.lastModified) ?? "—").foregroundStyle(.secondary) }.width(min: 100)
                        .customizationID("lastChanged").defaultVisibility(isProjects ? .hidden : .visible)
                    TableColumn("How") { item in Text(item.method.label).foregroundStyle(.secondary) }.width(min: 105).customizationID("how")
                    TableColumn("Size", value: \.size) { item in Text(FileSystem.format(item.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 85).customizationID("size")
                }
                .contextMenu(forSelectionType: CleanupItem.ID.self) { ids in
                    if let item = category.items.first(where: { ids.contains($0.id) }) {
                        if let url = item.paths.first { Button("Show in Finder", systemImage: "folder") { Permissions.reveal(url) } }
                        Button("Copy Command", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.technicalDescription, forType: .string) }
                    }
                } primaryAction: { _ in }
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
                }.padding(20)
            }
        }
    }
}

private extension CleanupItem {
    var sortableLastCommit: Date { lastCommit ?? .distantPast }
}
