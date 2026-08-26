import XCTest
@testable import CellarCore

final class MaintenanceServiceTests: XCTestCase {
    func testRefreshMergesInventoryServicesShellEventsAndCaskMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CellarStore(directory: directory)
        let eventURL = directory.appending(path: "events.log")
        try "1\t1800000000\tformula\tjq\n".write(to: eventURL, atomically: true, encoding: .utf8)
        let source = StubHomebrewSource(
            inventory: Data(Self.inventoryFixture.utf8),
            services: Data(#"[{"name":"jq","status":"started"}]"#.utf8)
        )
        let caskUsage = StubCaskUsage(dates: [
            "/Applications/Visual Studio Code.app": Date(timeIntervalSince1970: 1_750_000_000),
        ])
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        let summary = try MaintenanceService(
            store: store,
            eventLog: UsageEventLog(url: eventURL),
            homebrew: source,
            caskUsage: caskUsage,
            now: { now }
        ).run()

        XCTAssertEqual(summary.packageCount, 2)
        XCTAssertEqual(summary.acceptedEvents, 1)
        let packages = try store.packages()
        let jq = try XCTUnwrap(packages.first { $0.id == "formula:jq" })
        XCTAssertTrue(jq.isRunningService)
        XCTAssertEqual(jq.lastUsedAt, Date(timeIntervalSince1970: 1_800_000_000))
        let vscode = try XCTUnwrap(packages.first { $0.id == "cask:visual-studio-code" })
        XCTAssertEqual(vscode.lastUsedAt, Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertEqual(vscode.evidenceSource, .launchServices)
        XCTAssertEqual(try store.metadata("last-refresh"), "1900000000")
    }

    private static let inventoryFixture = #"""
    {
      "formulae": [{
        "name": "jq", "full_name": "jq", "pinned": false,
        "installed": [{"time": 1600000000, "installed_on_request": true, "runtime_dependencies": []}],
        "service": {}
      }],
      "casks": [{
        "token": "visual-studio-code", "full_token": "visual-studio-code",
        "installed": "1", "installed_time": 1600000000, "pinned": false,
        "depends_on": {},
        "artifacts": [{"app":["Visual Studio Code.app"],"target":["/Applications/Visual Studio Code.app"]}]
      }]
    }
    """#
}

private struct StubHomebrewSource: HomebrewDataSource {
    let inventory: Data
    let services: Data

    func installedInventory() throws -> Data { inventory }
    func serviceInventory() throws -> Data { services }
    func startService() throws {}
    func stopService() throws {}
    func orphanedDependencies() throws -> String { "" }
}

private struct StubCaskUsage: CaskUsageProviding {
    let dates: [String: Date]
    func lastUsedDate(forAppAt path: String) -> Date? { dates[path] }
}
