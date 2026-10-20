import AppKit
import CleanerKit
import SwiftUI

/// Provides the "Clean Build Files with MacCleaner" item in Finder's right-click menu
/// (Services / Quick Actions). Declared under NSServices in Info.plist.
final class FinderService: NSObject {
    let onFolders: @MainActor ([URL]) -> Void

    init(onFolders: @escaping @MainActor ([URL]) -> Void) {
        self.onFolders = onFolders
    }

    /// Called by macOS with the selected folders on the pasteboard. The selector name matches NSMessage.
    @objc func cleanBuildFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let folders = urls.filter { FileSystem.isDirectory($0) }
        guard !folders.isEmpty else {
            error.pointee = "Select one or more project folders." as NSString
            return
        }
        MainActor.assumeIsolated {
            NSApp.activate()
            onFolders(folders)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var service: FinderService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        service = FinderService { [weak self] folders in self?.model?.folderRequest = FolderRequest(folders: folders) }
        NSApp.servicesProvider = service
        NSUpdateDynamicServices()
    }
}

/// Sheet shown when folders arrive from Finder: lists their build folders and cleans the ticked ones.
struct FolderCleanSheet: View {
    let request: FolderRequest
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CleanupItem]?
    @State private var selected = Set<String>()
    @State private var report: CleanReport?
    @State private var isCleaning = false

    private var title: String {
        request.folders.count == 1 ? request.folders[0].lastPathComponent : "\(request.folders.count) folders"
    }
    private var selectedItems: [CleanupItem] { (items ?? []).filter { selected.contains($0.id) } }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean Build Files in \(title)").font(.title2.weight(.semibold))
                    Text(request.folders.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", "))
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            content
            HStack {
                if report == nil {
                    Button("Copy Script") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ShellScript.make(for: selectedItems), forType: .string)
                    }.disabled(selectedItems.isEmpty)
                }
                Spacer()
                if report == nil {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Delete \(FileSystem.format(selectedSize))") { Task { await clean() } }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(selectedItems.isEmpty || isCleaning)
                } else {
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 420)
        .task {
            let found = await CleanupEngine.buildFiles(in: request.folders)
            items = found
            selected = Set(found.map(\.id))
        }
    }

    @ViewBuilder private var content: some View {
        if let report {
            ContentUnavailableView {
                Label("Freed \(FileSystem.format(report.deletedBytes))", systemImage: "checkmark.circle.fill")
            } description: {
                Text(report.failures.isEmpty ? "Run the project's install or build command to recreate them."
                     : report.failures.map(\.message).joined(separator: "\n"))
            }
        } else if isCleaning {
            ProgressView("Deleting…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let items {
            if items.isEmpty {
                ContentUnavailableView("No Build Files Found", systemImage: "checkmark.seal",
                                       description: Text("These folders have no node_modules, build, .next, .dart_tool or similar folders over 10 MB."))
            } else {
                List(items) { item in
                    Toggle(isOn: Binding(get: { selected.contains(item.id) },
                                         set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.paths.first?.lastPathComponent ?? item.title)
                                Text(item.subtitle ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(FileSystem.format(item.size)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }
        } else {
            ProgressView("Looking for build folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func clean() async {
        isCleaning = true
        report = await CleanupEngine().clean(selectedItems)
        isCleaning = false
    }
}
