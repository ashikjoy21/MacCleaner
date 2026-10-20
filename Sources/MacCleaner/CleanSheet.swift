import CleanerKit
import SwiftUI

struct ConfirmationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private enum Group: String, CaseIterable { case deleted = "Deleted permanently (rebuilds automatically)", trash = "Moved to Trash", commands = "Commands" }
    private func items(for group: Group) -> [CleanupItem] {
        model.selectedItems.filter { item in
            switch (group, item.method) {
            case (.deleted, .delete): true
            case (.trash, .moveToTrash): true
            case (.commands, .command): true
            default: false
            }
        }
    }
    private func size(_ items: [CleanupItem]) -> Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clean Up \(FileSystem.format(model.selectedBytes))?").font(.title2.weight(.semibold)).padding(.bottom, 16)
            List {
                ForEach(Group.allCases, id: \.self) { group in
                    let entries = items(for: group)
                    if !entries.isEmpty {
                        Section { ForEach(entries) { item in HStack { Text(item.title); Spacer(); Text(FileSystem.format(item.size)).foregroundStyle(.secondary).monospacedDigit() } } }
                        header: { HStack { Text(group.rawValue); Spacer(); Text(FileSystem.format(size(entries))).foregroundStyle(.secondary).monospacedDigit() } }
                    }
                }
                if !model.appsToQuit.isEmpty { Section { ForEach(model.appsToQuit, id: \.bundleID) { app in Label("\(app.name) will be quit before cleaning.", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) } } }
            }.listStyle(.inset)
            HStack { Button("Copy Script") { model.copyShellScript() }.disabled(model.selectedItems.isEmpty)
                Spacer(); Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clean Up") { Task { await model.clean() } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
                .padding(.top, 16)
        }
        .padding(24).frame(minWidth: 520, minHeight: 420)
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
