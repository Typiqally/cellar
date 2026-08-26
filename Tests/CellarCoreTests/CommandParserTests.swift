import XCTest
@testable import CellarCore

final class CommandParserTests: XCTestCase {
    func testParsesReportFiltersAndJSON() throws {
        XCTAssertEqual(
            try CellarCommandParser.parse(["report", "--all", "--casks", "--json"]),
            .report(ReportOptions(showAll: true, kind: .cask, json: true, orphans: false))
        )
    }

    func testParsesConfigurationCommands() throws {
        XCTAssertEqual(try CellarCommandParser.parse(["config"]), .config(.show))
        XCTAssertEqual(try CellarCommandParser.parse(["config", "set", "stale-days", "120"]), .config(.setStaleDays(120)))
        XCTAssertEqual(try CellarCommandParser.parse(["config", "set", "notice", "changed"]), .config(.setNotice(.changed)))
        XCTAssertEqual(try CellarCommandParser.parse(["config", "reset", "notice"]), .config(.reset("notice")))
    }

    func testParsesSetupAndTeardownSafetyFlags() throws {
        XCTAssertEqual(
            try CellarCommandParser.parse(["setup", "--bootstrap-history", "--history-file", "/tmp/history", "--no-service"]),
            .setup(SetupOptions(bootstrapHistory: true, historyFile: "/tmp/history", startService: false))
        )
        XCTAssertEqual(try CellarCommandParser.parse(["teardown", "--purge", "--yes"]), .teardown(purge: true, confirmed: true))
    }

    func testRejectsUnknownOptionsAndInvalidValues() {
        XCTAssertThrowsError(try CellarCommandParser.parse(["report", "--wat"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["config", "set", "stale-days", "0"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["config", "set", "notice", "sometimes"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["teardown", "--purge"]))
    }
}
