import CleanerKit
import SwiftUI

struct ConfirmationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var groups: [(category: CategoryResult, items: [CleanupItem])] {
        model.scopedCategories.compactMap { category in
            let items = category.items.filter { model.selectedItemIDs.contains($0.id) }
            return items.isEmpty ? nil : (category, items)
        }
    }

    private var title: String {
        let size = FileSystem.format(model.scopedBytes)
        if model.cleanScope != nil, let category = groups.first?.category { return "Clean Up \(size) from \(category.name)?" }
        return "Clean Up \(size)?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title2.weight(.semibold))
            Text(model.cleanScope == nil ? "Everything ticked in every category." : "Only the items ticked in this category.")
                .foregroundStyle(.secondary).padding(.bottom, 16)
            List {
                ForEach(groups, id: \.category.id) { group in
                    Section {
                        ForEach(group.items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).lineLimit(1)
                                    if let detail = detail(for: item) {
                                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                Text(FileSystem.format(item.size)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    } header: {
                        HStack {
                            Label(group.category.name, systemImage: group.category.symbol)
                            Text(methodSummary(group.items)).foregroundStyle(.secondary)
                            Spacer()
                            Text(FileSystem.format(group.items.reduce(0) { $0 + $1.size })).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                if !model.scopedAppsToQuit.isEmpty {
                    Section {
                        ForEach(model.scopedAppsToQuit, id: \.bundleID) { app in
                            Label("\(app.name) will be quit before cleaning.", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        }
                    }
                }
            }.listStyle(.inset)
            HStack {
                Button("Copy Script") { model.copyShellScript(scopedOnly: true) }.disabled(model.scopedItems.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clean Up") { Task { await model.clean() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.scopedItems.isEmpty)
            }
            .padding(.top, 16)
        }
        .padding(24).frame(minWidth: 560, minHeight: 440)
    }

    /// The folder or file name under the title, so "abc-dashboard/client" rows say node_modules or .next.
    private func detail(for item: CleanupItem) -> String? {
        guard let first = item.paths.first else { return item.subtitle }
        if item.paths.count > 1 { return "\(item.paths.count) items · \(first.deletingLastPathComponent().lastPathComponent)" }
        return first.lastPathComponent == item.title ? item.subtitle : first.lastPathComponent
    }

    private func methodSummary(_ items: [CleanupItem]) -> String {
        let labels = Set(items.map(\.method.label))
        return "· " + labels.sorted().joined(separator: ", ").lowercased()
    }
}

struct CleanSheet: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 18) {
            if let report = model.cleanReport {
                result(report)
            } else {
                ProgressView(value: model.cleanProgress?.fraction ?? 0)
                    .progressViewStyle(.linear).frame(width: 320)
                Text("Cleaning…").font(.title2.weight(.semibold))
                Text(model.cleanProgress?.currentTitle ?? "Preparing…").foregroundStyle(.secondary).lineLimit(1)
                Text("\(model.cleanProgress?.completedItems ?? 0) of \(model.cleanProgress?.totalItems ?? 0) items")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(32).frame(minWidth: 460, minHeight: 320)
        .interactiveDismissDisabled(model.isCleaning)
    }

    @ViewBuilder private func result(_ report: CleanReport) -> some View {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.tint)
        Text("Freed \(FileSystem.format(report.deletedBytes))").font(.largeTitle.weight(.semibold))
        if report.trashedBytes > 0 {
            Text("\(FileSystem.format(report.trashedBytes)) was moved to the Trash. Empty the Trash to free that space.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open Trash") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }
                .buttonStyle(.bordered)
        }
        if !report.failures.isEmpty {
            DisclosureGroup("\(report.failures.count) item(s) could not be cleaned") {
                ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(report.failures) { failure in VStack(alignment: .leading, spacing: 2) { Text(failure.itemTitle).font(.headline); Text(failure.message).foregroundStyle(.secondary) } } }.frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 120)
            }.frame(maxWidth: 400)
        }
        Button("Done") { model.finishClean() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).padding(.top, 6)
    }
}
