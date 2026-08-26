import Foundation

public struct CellarPaths: Equatable, Sendable {
    public let stateDirectory: URL
    public var events: URL { stateDirectory.appending(path: "events.log") }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        if let override = environment["CELLAR_STATE_DIR"], !override.isEmpty {
            stateDirectory = URL(fileURLWithPath: override).standardizedFileURL
        } else {
            stateDirectory = homeDirectory
                .appending(path: "Library/Application Support/Cellar", directoryHint: .isDirectory)
                .standardizedFileURL
        }
    }
}
