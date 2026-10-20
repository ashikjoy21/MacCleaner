// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cleanerctl", targets: ["cleanerctl"]),
        .library(name: "CleanerKit", targets: ["CleanerKit"]),
    ],
    targets: [
        // Scanning and cleanup engine. No UI code lives here.
        .target(name: "CleanerKit", linkerSettings: [.linkedLibrary("sqlite3")]),
        // The SwiftUI app in Sources/MacCleaner is built by MacCleaner.xcodeproj (see project.yml),
        // which App Intents need for Shortcuts and Spotlight.
        // Command-line front end for checking the engine: `swift run cleanerctl`.
        .executableTarget(name: "cleanerctl", dependencies: ["CleanerKit"]),
        .testTarget(name: "CleanerKitTests", dependencies: ["CleanerKit"]),
    ],
    swiftLanguageModes: [.v5]
)
