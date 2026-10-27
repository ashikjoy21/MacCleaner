import CleanerKit
import SwiftUI

/// First-launch guide: what MacCleaner does and how to grant Full Disk Access.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasAccess = Permissions.hasFullDiskAccess
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("Welcome to MacCleaner").font(.largeTitle.weight(.semibold))
                Text("See what's using your disk, down to the folder, and free it safely.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                point("magnifyingglass", "Scans, never surprises",
                      "Scanning only reads. Nothing is removed until you review it and click Clean Up.")
                point("arrow.uturn.backward", "Recoverable by default",
                      "Personal files go to the Trash with Put Back. Only caches that rebuild themselves are deleted.")
                point("terminal", "Shows its work",
                      "Every item shows the exact command or path, and any selection can be copied as a shell script.")
            }
            .frame(maxWidth: 440)

            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: hasAccess ? "checkmark.circle.fill" : "lock.circle")
                        .font(.title).foregroundStyle(hasAccess ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasAccess ? "Full Disk Access is on" : "Allow Full Disk Access").font(.headline)
                        Text(hasAccess ? "MacCleaner can see app data like WhatsApp, Telegram and the Trash."
                                       : "Needed to look inside other apps' data and the Trash. Turn on MacCleaner in the list, then come back.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !hasAccess { Button("Open Settings") { Permissions.openFullDiskAccessSettings() } }
                }
                .padding(6)
            }
            .frame(maxWidth: 480)

            Button(hasAccess ? "Start Scanning" : "Continue Without It") { dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(36)
        .frame(width: 560)
        .onReceive(timer) { _ in hasAccess = Permissions.hasFullDiskAccess }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
