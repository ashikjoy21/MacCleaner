import CleanerKit
import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await model.scan()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Save Shell Script…") { model.saveShellScript() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.isScanning || model.selectedItems.isEmpty)
            }
        }
        .defaultSize(width: 1050, height: 720)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Label("Overview", systemImage: "chart.pie").tag("overview")
                ForEach(CategorySection.allCases, id: \.self) { section in
                    let categories = model.categories.filter { $0.section == section }
                    if !categories.isEmpty { Section(section.title) {
                    ForEach(categories) { category in
                        HStack(spacing: 8) {
                            Label(category.name, systemImage: category.symbol).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(FileSystem.format(category.totalSize)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).layoutPriority(1)
                        }.tag(category.id)
                    }
                    } }
                }
            }
            .navigationTitle("MacCleaner")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } detail: {
            Group {
                if let id = model.selection, id != "overview", let category = model.results[id] {
                    CategoryDetailView(category: category).id(category.id)
                } else {
                    OverviewView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .disabled(model.isScanning || model.isCleaning)
                }
                ToolbarItem(placement: .automatic) {
                    Button { model.copyShellScript() } label: { Label("Copy as Shell Script", systemImage: "terminal") }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .disabled(model.isScanning || model.selectedItems.isEmpty)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Clean Up…") { model.showingConfirmation = true }
                        .keyboardShortcut(.delete, modifiers: [.command])
                        .disabled(model.selectedBytes == 0 || model.isCleaning || model.isScanning)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { if model.selection == nil { model.selection = "overview" } }
        .sheet(isPresented: $model.showingConfirmation) { ConfirmationView() }
        .sheet(isPresented: $model.showingCleanSheet) { CleanSheet() }
    }
}
