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

        XCTAssertEqual(harness.output.text.components(separatedBy: "Cellar:").count - 1, 1)
        XCTAssertTrue(harness.output.text.contains("aged past 90 days"))
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

    func testInteractiveManagementCommandsCoverTheFullLifecycle() throws {
        let harness = try Harness(now: Date(timeIntervalSince1970: 2_000_000_000))
        try harness.store.replaceInventory([Harness.stalePackage])
        harness.homebrew.orphanedOutput = "Would autoremove libexample\n"

        XCTAssertEqual(try harness.application.run(.initZsh), 0)
        XCTAssertEqual(try harness.application.run(.version), 0)
        XCTAssertEqual(try harness.application.run(.help), 0)
        XCTAssertEqual(try harness.application.run(.completionsZsh), 0)
        XCTAssertEqual(try harness.application.run(.report(ReportOptions(showAll: true, kind: .formula))), 0)
        XCTAssertEqual(try harness.application.run(.explain("ripgrep")), 0)
        XCTAssertThrowsError(try harness.application.run(.explain("missing")))
        XCTAssertEqual(try harness.application.run(.ignore("ripgrep")), 0)
        XCTAssertEqual(try harness.application.run(.ignored), 0)
        XCTAssertEqual(try harness.application.run(.unignore("ripgrep")), 0)
        XCTAssertEqual(try harness.application.run(.config(.show)), 0)
        XCTAssertEqual(try harness.application.run(.config(.setNotice(.changed))), 0)
        XCTAssertEqual(try harness.application.run(.config(.reset("all"))), 0)
        XCTAssertEqual(try harness.application.run(.status), 0)
        XCTAssertEqual(try harness.application.run(.doctor), 0)
        XCTAssertEqual(try harness.application.run(.report(ReportOptions(orphans: true))), 0)
        XCTAssertEqual(try harness.application.run(.refresh), 0)
        XCTAssertEqual(try harness.application.run(.status), 0)
        XCTAssertEqual(try harness.application.run(.maintain), 0)
        XCTAssertEqual(try harness.application.run(.teardown(purge: false, confirmed: false)), 0)

        XCTAssertEqual(harness.homebrew.stopCount, 1)
        XCTAssertTrue(harness.output.text.contains("Would autoremove libexample"))
        XCTAssertTrue(harness.output.text.contains("Last refresh: never"))
        XCTAssertTrue(harness.output.text.contains("Last refresh: 2033"))
        XCTAssertTrue(harness.output.text.contains("State: candidate"))
        XCTAssertTrue(harness.output.text.contains("Cellar service stopped; local state preserved."))
    }

    func testSetupCanImportPackageOnlyHistoryWithoutStartingService() throws {
        let harness = try Harness()
        let executable = harness.formulaBin.appending(path: "jq")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let history = harness.directory.appending(path: ".zsh_history")
        try ": 1700000000:0;jq --secret never-store-this\n".write(to: history, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try harness.application.run(.setup(SetupOptions(bootstrapHistory: true, startService: false))),
            0
        )

        let package = try XCTUnwrap(harness.store.packages().first)
        XCTAssertEqual(package.lastUsedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(package.evidenceSource, .history)
        XCTAssertEqual(harness.homebrew.startCount, 0)
        XCTAssertFalse(harness.output.text.contains("never-store-this"))
    }

    func testSetupReportsUnreadableHistoryAndNoticeCanStaySilent() throws {
        let harness = try Harness()

        XCTAssertThrowsError(try harness.application.run(.setup(SetupOptions(
            bootstrapHistory: true,
            historyFile: harness.directory.appending(path: "missing-history").path,
            startService: false
        ))))
        XCTAssertEqual(try harness.application.run(.notice), 0)
        XCTAssertFalse(harness.output.text.contains("Cellar:"))
    }

    func testTeardownPurgeRequiresConfirmationAndRemovesState() throws {
        let unsafeHarness = try Harness()
        XCTAssertThrowsError(try unsafeHarness.application.run(.teardown(purge: true, confirmed: false)))

        let harness = try Harness()
        XCTAssertEqual(try harness.application.run(.teardown(purge: true, confirmed: true)), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.directory.path))
        XCTAssertTrue(harness.output.text.contains("local state removed"))
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
    let formulaBin: URL

    init(now: Date = Date(timeIntervalSince1970: 2_000_000_000)) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        store = try CellarStore(directory: directory)
        formulaBin = directory.appending(path: "Cellar/jq/1.0/bin")
        try FileManager.default.createDirectory(at: formulaBin, withIntermediateDirectories: true)
        homebrew = ApplicationHomebrewStub(prefix: directory.path)
        application = CellarApplication(
            store: store,
            paths: CellarPaths(environment: ["CELLAR_STATE_DIR": directory.path], homeDirectory: directory),
            homebrew: homebrew,
            caskUsage: ApplicationCaskUsageStub(),
            environment: ["PATH": formulaBin.path],
            homeDirectory: directory,
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
    private(set) var stopCount = 0
    var orphanedOutput = ""
    let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func installedInventory() throws -> Data {
        Data(#"{"formulae":[{"name":"jq","full_name":"jq","pinned":false,"installed":[{"time":1600000000,"installed_on_request":true,"runtime_dependencies":[]}],"service":null}],"casks":[]}"#.utf8)
    }
    func serviceInventory() throws -> Data { Data("[]".utf8) }
    func startService() throws { startCount += 1 }
    func stopService() throws { stopCount += 1 }
    func orphanedDependencies() throws -> String { orphanedOutput }
    func homebrewPrefix() throws -> String { prefix }
}

private struct ApplicationCaskUsageStub: CaskUsageProviding {
    func lastUsedDate(forAppAt path: String) -> Date? { nil }
}

private final class OutputCapture {
    private(set) var text = ""
    func write(_ value: String) { text += value }
}
