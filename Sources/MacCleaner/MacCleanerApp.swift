import CleanerKit
import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appDelegate.model = model
                    await UpdateChecker.shared.checkIfDue()
                }
                .task { await model.scan() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await UpdateChecker.shared.check(); model.showingUpdateResult = true } }
            }
            CommandGroup(replacing: .newItem) {
                Button("Save Shell Script…") { model.saveShellScript() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.isScanning || model.selectedItems.isEmpty)
            }
        }
        .defaultSize(width: 1050, height: 720)

        Settings {
            SettingsView()
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    private var updateAlertTitle: String {
        if let release = UpdateChecker.shared.available { return "MacCleaner \(release.version) is available" }
        return UpdateChecker.shared.lastError == nil ? "MacCleaner is up to date" : "Couldn't check for updates"
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Label("Overview", systemImage: "chart.pie").tag("overview")
                Label("File Browser", systemImage: "folder.badge.questionmark").tag("browser")
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
            .navigationSplitViewColumnWidth(min: 270, ideal: 290, max: 360)
        } detail: {
            Group {
                if model.selection == "browser" {
                    FileBrowserView()
                } else if let id = model.selection, id != "overview", let category = model.results[id] {
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
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { if model.selection == nil { model.selection = "overview" } }
        .sheet(isPresented: $model.showingConfirmation) { ConfirmationView() }
        .sheet(isPresented: $model.showingCleanSheet) { CleanSheet() }
        .sheet(isPresented: $model.showingWelcome) { WelcomeView() }
        .alert(updateAlertTitle, isPresented: $model.showingUpdateResult) {
            if UpdateChecker.shared.available != nil {
                Button("Update Now") { UpdateChecker.shared.install() }
                Button("Later", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(UpdateChecker.shared.lastError ?? UpdateChecker.shared.available?.notes ?? "You have the latest version, \(UpdateChecker.shared.currentVersion).")
        }
        .sheet(item: $model.folderRequest, onDismiss: { Task { await model.scan() } }) { request in FolderCleanSheet(request: request) }
    }
}
