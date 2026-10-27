import CleanerKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    private var usage: DiskUsage { DiskUsage.current() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You can free up \(FileSystem.format(model.selectedBytes))").font(.largeTitle.weight(.semibold)).monospacedDigit()
                        Text("Across \(model.projectCount) projects and \(model.toolCount) tools · \(FileSystem.format(usage.availableBytes)) available on Macintosh HD")
                            .foregroundStyle(.secondary)
                    }
                    StorageBar(usage: usage, selectedBytes: model.selectedBytes)
                    if model.isScanning { Label("Scanning…", systemImage: "arrow.triangle.2.circlepath").font(.callout).foregroundStyle(.secondary) }
                    if let projects = model.projectCategory {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Projects").font(.title2.weight(.semibold))
                                Spacer()
                                Button("Show All Projects") { model.selection = projects.id }
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(model.projectGroups.prefix(5))) { group in ProjectOverviewRow(group: group) }
                            }.background(.background, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    ForEach(CategorySection.allCases.filter { $0 != .projects }, id: \.self) { section in
                        let categories = model.categories.filter { $0.section == section }
                        if !categories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title).font(.title2.weight(.semibold))
                                VStack(spacing: 0) {
                                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                        CategoryOverviewRow(category: category)
                                        if index < categories.count - 1 { Divider().padding(.leading, 52) }
                                    }
                                }.background(.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding(28)
            }
            HStack { Spacer(); Button("Clean Up All Selected…") { model.requestCleanUp() }.keyboardShortcut(.delete, modifiers: [.command])
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.selectedBytes == 0 || model.isCleaning || model.isScanning) }
                .padding([.horizontal, .bottom], 24).padding(.top, 12)
        }
    }
}

private struct ProjectOverviewRow: View {
    @Environment(AppModel.self) private var model
    let group: ProjectGroup
    private var selectedCount: Int { group.items.filter { model.selectedItemIDs.contains($0.id) }.count }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer").foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title).font(.headline)
                HStack(spacing: 8) {
                    Text(group.folders).foregroundStyle(.secondary)
                    if let branch = group.branch {
                        Text(branch).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                    }
                    if let date = group.lastCommit { Text("last commit \(FileSystem.relative(date) ?? "recently")").foregroundStyle(.secondary) }
                }.font(.caption).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(FileSystem.format(group.size)).monospacedDigit().foregroundStyle(.secondary)
            Toggle("Select \(group.title)", isOn: Binding(
                get: { selectedCount == group.items.count },
                set: { on in for item in group.items where model.selectedItemIDs.contains(item.id) != on { model.toggle(item) } }))
                .labelsHidden().accessibilityLabel("Select \(group.title)")
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
}

private struct CategoryOverviewRow: View {
    @Environment(AppModel.self) private var model
    let category: CategoryResult
    private var selected: Int64 { model.selectedBytes(in: category) }
    private var isAllSelected: Bool { selected == category.totalSize && category.totalSize > 0 }
    private var isPartiallySelected: Bool { selected > 0 && !isAllSelected }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) { Text(category.name).font(.headline); Text(category.safety.label).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule()) }
                Text(category.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(model.sizeLabel(for: category)).monospacedDigit().foregroundStyle(.secondary)
            Button { model.setCategory(category, selected: !isAllSelected) } label: {
                Image(systemName: isPartiallySelected ? "minus.square" : (isAllSelected ? "checkmark.square.fill" : "square"))
                    .font(.title3).foregroundStyle(isAllSelected ? Color.accentColor : Color.secondary)
            }.buttonStyle(.plain).accessibilityLabel("Select \(category.name)").accessibilityValue(isPartiallySelected ? "Partially selected" : (isAllSelected ? "Selected" : "Not selected"))
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture { model.selection = category.id }
    }
}

struct StorageBar: View {
    let usage: DiskUsage
    let selectedBytes: Int64
    private var total: Double { Double(max(usage.totalBytes, 1)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let used = min(width, max(0, width * CGFloat(usage.usedFraction)))
                let selected = min(used, width * CGFloat(Double(selectedBytes) / total))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.secondary.opacity(0.42)).frame(width: used)
                    Capsule().fill(.tint).frame(width: selected)
                }
            }
            .frame(height: 13)
            .accessibilityElement().accessibilityLabel("Disk usage").accessibilityValue("\(FileSystem.format(usage.usedBytes)) used, \(FileSystem.format(selectedBytes)) selected for cleanup, \(FileSystem.format(usage.availableBytes)) available")
            HStack(spacing: 18) {
                Legend(color: .secondary.opacity(0.55), title: "Used")
                Legend(color: Color.accentColor, title: "Selected for cleanup")
                Legend(color: Color.secondary.opacity(0.18), title: "Available")
                Spacer()
                Text("\(FileSystem.format(usage.totalBytes)) total").foregroundStyle(.secondary)
            }.font(.caption)
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct Legend: View {
    let color: Color
    let title: String
    var body: some View { Label(title, systemImage: "circle.fill").labelStyle(LegendLabel(color: color)) }
}
private struct LegendLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 5) { configuration.icon.foregroundStyle(color); configuration.title.foregroundStyle(.secondary) } }
}
