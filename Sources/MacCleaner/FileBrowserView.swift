import AppKit
import CleanerKit
import QuickLook
import SwiftUI

/// Browse any folder in your home folder with sizes, like System Settings › Storage › File Browser,
/// and move what you don't need to the Trash.
struct FileBrowserView: View {
    private static let browser = FolderBrowser()
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @State private var path: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @State private var entries: [FolderBrowser.Entry] = []
    @State private var sizes: [URL: Int64] = [:]
    @State private var selection = Set<URL>()
    @State private var sortOrder = [KeyPathComparator(\Row.sortSize, order: .reverse)]
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var pendingTrash: [URL] = []
    @State private var message: String?
    @State private var loadTask: Task<Void, Never>?

    private var folder: URL { path.last ?? home }

    struct Row: Identifiable {
        let entry: FolderBrowser.Entry
        let size: Int64?
        var id: URL { entry.url }
        var name: String { entry.name }
        var sortSize: Int64 { size ?? -1 }
        var modified: Date { entry.modified ?? .distantPast }
    }

    private var rows: [Row] { entries.map { Row(entry: $0, size: sizes[$0.url]) }.sorted(using: sortOrder) }
    private var folderTotal: Int64 { sizes.filter { url, _ in entries.contains { $0.url == url } }.values.reduce(0, +) }
    private var isMeasuring: Bool { entries.contains { sizes[$0.url] == nil } }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            table
            Divider()
            bottomBar
        }
        .navigationTitle("File Browser")
        .task(id: folder) { load() }
        .confirmationDialog(trashTitle, isPresented: Binding(get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } })) {
            Button("Move to Trash", role: .destructive) { Task { await trash(pendingTrash) } }
            Button("Cancel", role: .cancel) { pendingTrash = [] }
        } message: {
            Text("You can put items back from the Trash until it's emptied.")
        }
        .alert("Couldn't Move to Trash", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    // MARK: Parts

    private var pathBar: some View {
        HStack(spacing: 4) {
            Button { goUp() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless).disabled(path.count <= 1).help("Back")
                .keyboardShortcut("[", modifiers: .command)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(path.enumerated()), id: \.offset) { index, url in
                        if index > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                        Button { path = Array(path.prefix(index + 1)) } label: {
                            Label(index == 0 ? "Home" : url.lastPathComponent,
                                  systemImage: index == 0 ? "house" : "folder")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                    }
                }
            }
            Spacer()
            if isMeasuring { ProgressView().controlSize(.small) }
            Text(FileSystem.format(folderTotal)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: row.entry.url.path)).resizable().frame(width: 18, height: 18)
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                    if row.entry.isFolder { Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }
            }
            .width(min: 220, ideal: 360)
            TableColumn("Modified", value: \.modified) { row in
                Text(FileSystem.relative(row.entry.modified) ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Size", value: \.sortSize) { row in
                Group {
                    if let size = row.size { Text(FileSystem.format(size)).monospacedDigit() }
                    else { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if urls.count == 1, let url = urls.first, entries.first(where: { $0.url == url })?.isFolder == true {
                Button("Open", systemImage: "folder") { open(url) }
            }
            Button("Quick Look", systemImage: "eye") { preview(urls) }
            Button("Show in Finder", systemImage: "magnifyingglass") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) { askToTrash(urls) }
                .disabled(!urls.allSatisfy { FolderBrowser.canTrash($0) })
        } primaryAction: { urls in
            guard let url = urls.first else { return }
            if entries.first(where: { $0.url == url })?.isFolder == true { open(url) } else { preview(urls) }
        }
        .onKeyPress(.space) {
            if previewURL != nil { previewURL = nil } else { preview(selection) }
            return .handled
        }
        .onKeyPress(.return) {
            if selection.count == 1, let url = selection.first, entries.first(where: { $0.url == url })?.isFolder == true { open(url) }
            return .handled
        }
        .onDeleteCommand { askToTrash(selection) }
        .quickLookPreview($previewURL, in: previewURLs)
    }

    private var bottomBar: some View {
        HStack {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(selection.isEmpty ? [folder] : Array(selection)) }
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) selected · \(FileSystem.format(selection.compactMap { sizes[$0] }.reduce(0, +)))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Button("Move to Trash…", role: .destructive) { askToTrash(selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selection.isEmpty || !selection.allSatisfy { FolderBrowser.canTrash($0) })
        }
        .padding(16)
    }

    // MARK: Actions

    private func load() {
        loadTask?.cancel()
        selection = []
        entries = Self.browser.entries(in: folder)
        sizes = [:]
        let current = entries
        loadTask = Task {
            for await (url, size) in Self.browser.sizes(for: current) {
                guard !Task.isCancelled else { return }
                sizes[url] = size
            }
        }
    }

    private func open(_ url: URL) { path.append(url) }

    private func goUp() { if path.count > 1 { path.removeLast() } }

    private func preview(_ urls: Set<URL>) {
        let list = rows.map(\.entry.url).filter { urls.contains($0) }
        guard !list.isEmpty else { return }
        previewURLs = list.map(QuickLookSupport.previewableURL)
        previewURL = previewURLs.first
    }

    private var trashTitle: String {
        let size = FileSystem.format(pendingTrash.compactMap { sizes[$0] }.reduce(0, +))
        if pendingTrash.count == 1, let url = pendingTrash.first { return "Move “\(url.lastPathComponent)” (\(size)) to the Trash?" }
        return "Move \(pendingTrash.count) items (\(size)) to the Trash?"
    }

    private func askToTrash(_ urls: Set<URL>) {
        let allowed = urls.filter { FolderBrowser.canTrash($0) }
        guard !allowed.isEmpty else {
            message = "Library, Documents and other standard folders can't be moved to the Trash from here."
            return
        }
        pendingTrash = Array(allowed)
    }

    private func trash(_ urls: [URL]) async {
        let items = urls.map { CleanupItem(id: $0.path, title: $0.lastPathComponent, paths: [$0], size: sizes[$0] ?? 0,
                                           method: .moveToTrash, isSelectedByDefault: true) }
        pendingTrash = []
        let report = await CleanupEngine().clean(items)
        if !report.failures.isEmpty { message = report.failures.map(\.message).joined(separator: "\n") }
        for url in urls { await Self.browser.invalidate(url) }
        load()
    }
}
