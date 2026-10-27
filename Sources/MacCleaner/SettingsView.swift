import AppKit
import CleanerKit
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    @AppStorage(SettingsStore.staleDaysKey) private var staleDays = 30
    @AppStorage(UpdateChecker.automaticKey) private var checkForUpdates = true
    /// Newline-separated paths; empty means the default folders.
    @AppStorage(SettingsStore.projectFoldersKey) private var storedFoldersText = ""
    private var storedFolders: [String] {
        get { storedFoldersText.split(separator: "\n").map(String.init) }
        nonmutating set { storedFoldersText = newValue.joined(separator: "\n") }
    }
    @State private var selection: String?

    /// Folders shown in the list: the user's own, or the defaults found on this Mac.
    private var folders: [String] {
        storedFolders.isEmpty ? CleanerSettings.defaultProjectFolders().map(\.path) : storedFolders
    }

    var body: some View {
        Form {
            Section {
                List(folders, id: \.self, selection: $selection) { path in
                    Label(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                        .font(.body.monospaced())
                }
                .frame(minHeight: 140)
                HStack {
                    Button("Add Folder…", systemImage: "plus") { addFolder() }
                    Button("Remove", systemImage: "minus") { remove() }.disabled(selection == nil)
                    Spacer()
                    Button("Use Defaults") { storedFolders = [] }.disabled(storedFolders.isEmpty)
                }
            } header: {
                Text("Project Folders")
            } footer: {
                Text("MacCleaner looks up to five levels deep in these folders for node_modules, build, .next, .dart_tool and similar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $staleDays, in: 1...365) {
                    LabeledContent("Tick projects inactive for", value: "\(staleDays) days")
                }
            } footer: {
                Text("A project is inactive when it has no commits and no edited files for this long. Changes apply on the next scan.")
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                LabeledContent("Version", value: UpdateChecker.shared.currentVersion)
            }

            Section("Finder") {
                LabeledContent("Quick Action") {
                    Text("Right-click a folder › Services › Clean Build Files with MacCleaner")
                        .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                Button("Open Keyboard Shortcuts for Services…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Services")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var updated = folders
        for url in panel.urls where !updated.contains(url.path) { updated.append(url.path) }
        storedFolders = updated
    }

    private func remove() {
        guard let selection else { return }
        storedFolders = folders.filter { $0 != selection }
        self.selection = nil
    }
}
