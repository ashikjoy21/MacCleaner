import Foundation

/// Android SDK system images no emulator uses, emulator user data, and old Gradle distributions.
struct AndroidCategory: CleanupCategory {
    let id = "android"
    let home: URL
    var now = Date()

    var sdk: URL { home.appendingPathComponent("Library/Android/sdk") }
    var avdFolder: URL { home.appendingPathComponent(".android/avd") }
    var gradleDists: URL { home.appendingPathComponent(".gradle/wrapper/dists") }

    func scan() async -> CategoryResult {
        let base = CategoryResult(
            id: id, name: "Android & Gradle",
            summary: "Emulator images, emulator data and Gradle versions you aren't using.",
            explanation: "System images under sdk/system-images that no emulator (AVD) points to can be reinstalled from "
                + "Android Studio's SDK Manager. Wiping an emulator deletes its userdata, cache and snapshots, the same as "
                + "Device Manager › Wipe Data; the emulator itself stays. Gradle downloads a distribution per version into "
                + "~/.gradle/wrapper/dists; every version except the newest is listed, and a project that pins an older one "
                + "downloads it again on its next build.",
            symbol: "apps.iphone", safety: .review)

        var items: [CleanupItem] = []
        items += unusedSystemImages()
        items += emulatorData()
        items += oldGradleDistributions()
        guard !items.isEmpty || FileSystem.isDirectory(sdk) || FileSystem.isDirectory(gradleDists) else {
            return base.with(status: .unavailable("Android tools aren't installed"))
        }
        return base.with(items: items)
    }

    /// The `image.sysdir.1` of every AVD, e.g. "system-images/android-35/google_apis/arm64-v8a/".
    func imagesInUse() -> Set<String> {
        let avds = (try? FileManager.default.contentsOfDirectory(at: avdFolder, includingPropertiesForKeys: nil)) ?? []
        var used = Set<String>()
        for avd in avds where avd.pathExtension == "avd" {
            guard let config = try? String(contentsOf: avd.appendingPathComponent("config.ini"), encoding: .utf8) else { continue }
            for line in config.split(separator: "\n") where line.hasPrefix("image.sysdir.") {
                if let value = line.split(separator: "=", maxSplits: 1).last {
                    used.insert(value.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))
                }
            }
        }
        return used
    }

    /// system-images/<api>/<tag>/<abi> folders no AVD uses.
    func unusedSystemImages() -> [CleanupItem] {
        let images = sdk.appendingPathComponent("system-images")
        let used = imagesInUse()
        var items: [CleanupItem] = []
        for api in subfolders(images) {
            for tag in subfolders(api) {
                for abi in subfolders(tag) {
                    let relative = "system-images/\(api.lastPathComponent)/\(tag.lastPathComponent)/\(abi.lastPathComponent)"
                    guard !used.contains(relative) else { continue }
                    items.append(CleanupItem(id: "android:image:\(relative)",
                                             title: "\(api.lastPathComponent) · \(tag.lastPathComponent) · \(abi.lastPathComponent)",
                                             subtitle: "System image no emulator uses", paths: [abi],
                                             size: FileSystem.allocatedSize(of: abi), method: .delete, isSelectedByDefault: true,
                                             lastModified: FileSystem.modificationDate(of: abi)))
                }
            }
        }
        return items
    }

    /// The data files inside each emulator: what "Wipe Data" removes.
    func emulatorData() -> [CleanupItem] {
        let dataFiles = ["userdata-qemu.img", "userdata-qemu.img.qcow2", "cache.img", "cache.img.qcow2", "snapshots"]
        return subfolders(avdFolder).filter { $0.pathExtension == "avd" }.compactMap { avd in
            let paths = dataFiles.map { avd.appendingPathComponent($0) }.filter(FileSystem.exists)
            let size = FileSystem.allocatedSize(of: paths)
            guard size > 50_000_000 else { return nil }
            return CleanupItem(id: "android:avd:\(avd.lastPathComponent)",
                               title: "\(avd.deletingPathExtension().lastPathComponent) data",
                               subtitle: "Wipe emulator data and snapshots", paths: paths, size: size, method: .delete,
                               isSelectedByDefault: false, lastModified: FileSystem.modificationDate(of: avd))
        }
    }

    /// Every Gradle distribution except the newest version.
    func oldGradleDistributions() -> [CleanupItem] {
        let dists = subfolders(gradleDists).filter { $0.lastPathComponent.hasPrefix("gradle-") }
        guard dists.count > 1 else { return [] }
        let newest = dists.max { Self.version(of: $0).lexicographicallyPrecedes(Self.version(of: $1)) }
        return dists.filter { $0 != newest }.map { dist in
            CleanupItem(id: "android:gradle:\(dist.lastPathComponent)", title: dist.lastPathComponent,
                        subtitle: "Older Gradle distribution · downloads again if a project needs it",
                        paths: [dist], size: FileSystem.allocatedSize(of: dist), method: .delete, isSelectedByDefault: true,
                        lastModified: FileSystem.modificationDate(of: dist))
        }
    }

    /// "gradle-9.3.1-all" → [9, 3, 1]
    static func version(of dist: URL) -> [Int] {
        let name = dist.lastPathComponent.dropFirst("gradle-".count)
        let numeric = name.split(separator: "-").first ?? ""
        return numeric.split(separator: ".").map { Int($0) ?? 0 }
    }

    private func subfolders(_ url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter(FileSystem.isDirectory)
    }
}
