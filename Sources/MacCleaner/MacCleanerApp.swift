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
            CommandGroup(replacing: .newItem) { }
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
                Section("Cleanup") {
                    ForEach(model.categories) { category in
                        HStack(spacing: 8) {
                            Label(category.name, systemImage: category.symbol).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(FileSystem.format(category.totalSize)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).layoutPriority(1)
                        }.tag(category.id)
                    }
                }
            }
            .navigationTitle("MacCleaner")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } detail: {
            Group {
                if let id = model.selection, id != "overview", let category = model.results[id] {
                    CategoryDetailView(category: category)
                } else {
                    OverviewView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .disabled(model.isScanning || model.isCleaning)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { if model.selection == nil { model.selection = "overview" } }
        .sheet(isPresented: $model.showingConfirmation) { ConfirmationView() }
        .sheet(isPresented: $model.showingCleanSheet) { CleanSheet() }
    }
}
