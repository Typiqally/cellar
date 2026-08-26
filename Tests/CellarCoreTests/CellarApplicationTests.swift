import XCTest
@testable import CellarCore

final class CellarApplicationTests: XCTestCase {
    func testSetupRefreshesStartsServiceAndPrintsManualZshLine() throws {
        let harness = try Harness()

        XCTAssertEqual(try harness.application.run(.setup(SetupOptions())), 0)

        XCTAssertEqual(harness.homebrew.startCount, 1)
        XCTAssertTrue(harness.output.text.contains("eval \"$(cellar init zsh)\""))
        XCTAssertEqual(try harness.store.packages().count, 1)
    }

    func testNoticePrintsOnlyOnceDaily() throws {
        let harness = try Harness(now: Date(timeIntervalSince1970: 2_000_000_000))
        try harness.store.replaceInventory([Harness.stalePackage])

        XCTAssertEqual(try harness.application.run(.notice), 0)
        XCTAssertEqual(try harness.application.run(.notice), 0)

        XCTAssertEqual(harness.output.text.components(separatedBy: "packages have aged").count - 1, 1)
        XCTAssertTrue(harness.output.text.contains("run 'cellar report'"))
    }

    func testConfigurationAndJSONReportCommands() throws {
        let harness = try Harness(now: Date(timeIntervalSince1970: 2_000_000_000))
        try harness.store.replaceInventory([Harness.stalePackage])

        XCTAssertEqual(try harness.application.run(.config(.setStaleDays(120))), 0)
        XCTAssertEqual(try harness.store.loadConfiguration().staleDays, 120)
        XCTAssertEqual(try harness.application.run(.report(ReportOptions(json: true))), 0)

        XCTAssertTrue(harness.output.text.contains("\"version\" : 1"))
        XCTAssertTrue(harness.output.text.contains("formula:ripgrep"))
    }
}

private final class Harness {
    static let stalePackage = TrackedPackage(
        id: "formula:ripgrep",
        name: "ripgrep",
        kind: .formula,
        installedOnRequest: true,
        isLeaf: true,
        isPinned: false,
        isRunningService: false,
        isIgnored: false,
        supportsUsageSignal: true,
        observedSince: Date(timeIntervalSince1970: 1_900_000_000),
        lastUsedAt: Date(timeIntervalSince1970: 1_900_000_000),
        evidenceSource: .shell
    )

    let directory: URL
    let store: CellarStore
    let homebrew: ApplicationHomebrewStub
    let output = OutputCapture()
    let application: CellarApplication

    init(now: Date = Date(timeIntervalSince1970: 2_000_000_000)) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        store = try CellarStore(directory: directory)
        homebrew = ApplicationHomebrewStub()
        application = CellarApplication(
            store: store,
            paths: CellarPaths(environment: ["CELLAR_STATE_DIR": directory.path], homeDirectory: directory),
            homebrew: homebrew,
            caskUsage: ApplicationCaskUsageStub(),
            now: { now },
            writeOutput: output.write
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class ApplicationHomebrewStub: HomebrewDataSource {
    private(set) var startCount = 0

    func installedInventory() throws -> Data {
        Data(#"{"formulae":[{"name":"jq","full_name":"jq","pinned":false,"installed":[{"time":1600000000,"installed_on_request":true,"runtime_dependencies":[]}],"service":null}],"casks":[]}"#.utf8)
    }
    func serviceInventory() throws -> Data { Data("[]".utf8) }
    func startService() throws { startCount += 1 }
    func stopService() throws {}
    func orphanedDependencies() throws -> String { "" }
}

private struct ApplicationCaskUsageStub: CaskUsageProviding {
    func lastUsedDate(forAppAt path: String) -> Date? { nil }
}

private final class OutputCapture {
    private(set) var text = ""
    func write(_ value: String) { text += value }
}
