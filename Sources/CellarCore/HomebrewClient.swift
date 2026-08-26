import Foundation

public struct ProcessRequest: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]

    public init(executable: URL, arguments: [String], environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public struct ProcessResult: Equatable, Sendable {
    public let stdout: Data
    public let stderr: Data
    public let status: Int32

    public init(stdout: Data, stderr: Data, status: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
    }
}

public protocol ProcessRunning {
    func run(_ request: ProcessRequest) throws -> ProcessResult
}

public enum ProcessExecutionError: LocalizedError {
    case executableNotFound
    case failed(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound: "Homebrew executable not found"
        case let .failed(status, message): "Homebrew exited with status \(status): \(message)"
        }
    }
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ request: ProcessRequest) throws -> ProcessResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let stdoutURL = temporaryDirectory.appending(path: "cellar-stdout-\(UUID().uuidString)")
        let stderrURL = temporaryDirectory.appending(path: "cellar-stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        try process.run()
        process.waitUntilExit()
        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()
        return ProcessResult(
            stdout: try Data(contentsOf: stdoutURL),
            stderr: try Data(contentsOf: stderrURL),
            status: process.terminationStatus
        )
    }
}

public final class HomebrewClient: HomebrewDataSource {
    public let brewURL: URL
    public var inferredPrefix: String {
        brewURL.deletingLastPathComponent().deletingLastPathComponent().path
    }
    private let runner: any ProcessRunning
    private let baseEnvironment: [String: String]

    public init(
        brewURL: URL,
        runner: any ProcessRunning = SystemProcessRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.brewURL = brewURL
        self.runner = runner
        var safeEnvironment = environment
        safeEnvironment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        baseEnvironment = safeEnvironment
    }

    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: any ProcessRunning = SystemProcessRunner()
    ) throws -> HomebrewClient {
        var candidates: [URL] = []
        if let prefix = environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            candidates.append(URL(fileURLWithPath: prefix).appending(path: "bin/brew"))
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/brew"))
        guard let brewURL = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ProcessExecutionError.executableNotFound
        }
        return HomebrewClient(brewURL: brewURL, runner: runner, environment: environment)
    }

    public func installedInventory() throws -> Data {
        try checkedRun(["info", "--json=v2", "--installed"]).stdout
    }

    public func serviceInventory() throws -> Data {
        try checkedRun(["services", "list", "--json"]).stdout
    }

    public func startService() throws {
        _ = try checkedRun(["services", "start", "cellar"])
    }

    public func stopService() throws {
        _ = try checkedRun(["services", "stop", "cellar"])
    }

    public func orphanedDependencies() throws -> String {
        String(decoding: try checkedRun(["autoremove", "--dry-run"]).stdout, as: UTF8.self)
    }

    public func homebrewPrefix() throws -> String {
        String(decoding: try checkedRun(["--prefix"]).stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkedRun(_ arguments: [String]) throws -> ProcessResult {
        let result = try runner.run(ProcessRequest(executable: brewURL, arguments: arguments, environment: baseEnvironment))
        guard result.status == 0 else {
            let decoded = String(decoding: result.stderr.prefix(4_096), as: UTF8.self)
            let message = decoded
                .unicodeScalars
                .filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }
                .map(String.init)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProcessExecutionError.failed(status: result.status, message: message.isEmpty ? "unknown error" : message)
        }
        return result
    }
}
