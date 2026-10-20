// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacCleaner", targets: ["MacCleaner"]),
        .executable(name: "cleanerctl", targets: ["cleanerctl"]),
        .library(name: "CleanerKit", targets: ["CleanerKit"]),
    ],
    targets: [
        // Scanning and cleanup engine. No UI code lives here.
        .target(name: "CleanerKit", linkerSettings: [.linkedLibrary("sqlite3")]),
        // SwiftUI app.
        .executableTarget(name: "MacCleaner", dependencies: ["CleanerKit"]),
        // Command-line front end for checking the engine: `swift run cleanerctl`.
        .executableTarget(name: "cleanerctl", dependencies: ["CleanerKit"]),
        .testTarget(name: "CleanerKitTests", dependencies: ["CleanerKit"]),
    ],
    swiftLanguageModes: [.v5]
)
