import Foundation

/// Runs command-line tools. Apps launched from Finder get a minimal PATH,
/// so tools are looked up in the usual install locations.
public enum Shell {
    static let searchPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin",
                              "/Applications/Docker.app/Contents/Resources/bin"]

    public static func which(_ tool: String) -> String? {
        if tool.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: tool) ? tool : nil }
        return searchPaths.map { "\($0)/\(tool)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public struct Result: Sendable {
        public let status: Int32
        public let output: String
        public let error: String
        public var succeeded: Bool { status == 0 }
    }

    /// Runs `argv` and waits for it, up to `timeout` seconds.
    public static func run(_ argv: [String], timeout: TimeInterval = 600) -> Result {
        guard let tool = argv.first, let path = which(tool) else {
            return Result(status: 127, output: "", error: "\(argv.first ?? "") not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = Array(argv.dropFirst())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":")
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Read pipes concurrently so a chatty command can't fill the pipe buffer and hang.
        let outData = LockedData(), errData = LockedData()
        out.fileHandleForReading.readabilityHandler = { outData.append($0.availableData) }
        err.fileHandleForReading.readabilityHandler = { errData.append($0.availableData) }
        do { try process.run() } catch {
            return Result(status: 126, output: "", error: error.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline { process.terminate(); break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        outData.append(out.fileHandleForReading.readDataToEndOfFile())
        errData.append(err.fileHandleForReading.readDataToEndOfFile())
        return Result(status: process.terminationStatus, output: outData.string, error: errData.string)
    }
}

private final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
