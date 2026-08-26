import XCTest
@testable import CellarCore

final class HomebrewClientTests: XCTestCase {
    func testUsesDirectBrewExecutableAndDisablesAutoUpdate() throws {
        let runner = RecordingProcessRunner(results: [
            ProcessResult(stdout: Data(#"{"formulae":[],"casks":[]}"#.utf8), stderr: Data(), status: 0),
        ])
        let client = HomebrewClient(brewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"), runner: runner)

        _ = try client.installedInventory()

        XCTAssertEqual(runner.requests.first?.executable.path, "/opt/homebrew/bin/brew")
        XCTAssertEqual(runner.requests.first?.arguments, ["info", "--json=v2", "--installed"])
        XCTAssertEqual(runner.requests.first?.environment["HOMEBREW_NO_AUTO_UPDATE"], "1")
    }

    func testServiceAndAutoremoveCommandsUseArgumentsWithoutAShell() throws {
        let runner = RecordingProcessRunner(results: [
            ProcessResult(stdout: Data(), stderr: Data(), status: 0),
            ProcessResult(stdout: Data(), stderr: Data(), status: 0),
            ProcessResult(stdout: Data("jq\n".utf8), stderr: Data(), status: 0),
        ])
        let client = HomebrewClient(brewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"), runner: runner)

        try client.startService()
        try client.stopService()
        XCTAssertEqual(try client.orphanedDependencies(), "jq\n")

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["services", "start", "cellar"],
            ["services", "stop", "cellar"],
            ["autoremove", "--dry-run"],
        ])
    }

    func testNonzeroExitReturnsSanitizedFailure() {
        let runner = RecordingProcessRunner(results: [
            ProcessResult(stdout: Data(), stderr: Data("brew failed\n".utf8), status: 1),
        ])
        let client = HomebrewClient(brewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"), runner: runner)

        XCTAssertThrowsError(try client.serviceInventory()) { error in
            XCTAssertTrue(error.localizedDescription.contains("brew failed"))
            XCTAssertFalse(error.localizedDescription.contains("stack"))
        }
    }
}

private final class RecordingProcessRunner: ProcessRunning {
    private var results: [ProcessResult]
    private(set) var requests: [ProcessRequest] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(_ request: ProcessRequest) throws -> ProcessResult {
        requests.append(request)
        return results.removeFirst()
    }
}
