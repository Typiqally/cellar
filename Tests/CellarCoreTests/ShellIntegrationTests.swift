import XCTest
@testable import CellarCore

final class ShellIntegrationTests: XCTestCase {
    func testZshIntegrationIsIdempotentPrivateAndProcessFreePerCommand() {
        let script = ShellIntegration.zshInit(executableName: "cellar")

        XCTAssertTrue(script.contains("add-zsh-hook preexec _cellar_preexec"))
        XCTAssertTrue(script.contains("command cellar notice"))
        XCTAssertTrue(script.contains("${(z)1}"))
        XCTAssertTrue(script.contains("events.log"))
        XCTAssertFalse(script.contains("eval $1"))
        XCTAssertFalse(script.contains("cellar record"))
    }

    func testZshHookWritesOnlyTabDelimitedPackageEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = directory.appending(path: "state")
        let prefix = directory.appending(path: "homebrew")
        let cellarBin = prefix.appending(path: "Cellar/ripgrep/1.0/bin")
        let toolsBin = directory.appending(path: "tools")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cellarBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toolsBin, withIntermediateDirectories: true)
        try Self.makeExecutable(at: cellarBin.appending(path: "rg"), contents: "#!/bin/sh\nexit 0\n")
        try Self.makeExecutable(at: toolsBin.appending(path: "cellar"), contents: "#!/bin/sh\nexit 0\n")
        let integration = directory.appending(path: "integration.zsh")
        try ShellIntegration.zshInit().write(to: integration, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-dfi"]
        process.environment = [
            "HOME": directory.path,
            "PATH": "\(toolsBin.path):\(cellarBin.path):/usr/bin:/bin",
            "HOMEBREW_PREFIX": prefix.path,
            "CELLAR_STATE_DIR": state.path,
            "TERM": "dumb",
        ]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data("source '\(integration.path)'\n_cellar_preexec 'rg super-secret-token'\nexit\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let event = try String(contentsOf: state.appending(path: "events.log"), encoding: .utf8)
        XCTAssertEqual(event.split(separator: "\t").count, 4)
        XCTAssertTrue(event.contains("\tformula\tripgrep\n"))
        XCTAssertFalse(event.contains("super-secret-token"))
    }

    private static func makeExecutable(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
