import AppKit
import Foundation
import Observation

/// Checks GitHub Releases for a newer version and installs it with the same script as the first install.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Decodable, Equatable {
        let version: String
        let notes: String?
        let url: String?
    }

    static let shared = UpdateChecker()
    static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"

    var available: Release?
    var isChecking = false
    var isInstalling = false
    var lastError: String?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private let repo = Bundle.main.object(forInfoDictionaryKey: "MCGitHubRepo") as? String ?? "ashikjoy21/MacCleaner"
    private var base: String { "https://github.com/\(repo)/releases/latest/download" }

    /// Checks at most once a day, unless the user turned automatic checks off.
    func checkIfDue() async {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.automaticKey) != nil, !defaults.bool(forKey: Self.automaticKey) { return }
        let last = defaults.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        await check()
    }

    func check() async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }
        do {
            var request = URLRequest(url: URL(string: "\(base)/latest.json")!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(Release.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            available = Self.isNewer(release.version, than: currentVersion) ? release : nil
        } catch {
            lastError = "Couldn't check for updates: \(error.localizedDescription)"
        }
    }

    /// Runs the installer, which quits this app, replaces it and opens the new version.
    func install() {
        isInstalling = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // nohup keeps the installer running after it quits this app.
        process.arguments = ["-c", "curl -fsSL '\(base)/install.sh' | /usr/bin/nohup /bin/sh >/tmp/maccleaner-update.log 2>&1 &"]
        do { try process.run() } catch {
            isInstalling = false
            lastError = "Couldn't start the update: \(error.localizedDescription)"
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
