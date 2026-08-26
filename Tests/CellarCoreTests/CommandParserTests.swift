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

    func testParsesSimpleCommandsAndAliases() throws {
        XCTAssertEqual(try CellarCommandParser.parse([]), .help)
        XCTAssertEqual(try CellarCommandParser.parse(["-h"]), .help)
        XCTAssertEqual(try CellarCommandParser.parse(["--version"]), .version)
        XCTAssertEqual(try CellarCommandParser.parse(["notice"]), .notice)
        XCTAssertEqual(try CellarCommandParser.parse(["explain", "jq"]), .explain("jq"))
        XCTAssertEqual(try CellarCommandParser.parse(["ignore", "--list"]), .ignored)
        XCTAssertEqual(try CellarCommandParser.parse(["ignore", "jq"]), .ignore("jq"))
        XCTAssertEqual(try CellarCommandParser.parse(["unignore", "jq"]), .unignore("jq"))
        XCTAssertEqual(try CellarCommandParser.parse(["status"]), .status)
        XCTAssertEqual(try CellarCommandParser.parse(["refresh"]), .refresh)
        XCTAssertEqual(try CellarCommandParser.parse(["maintain"]), .maintain)
        XCTAssertEqual(try CellarCommandParser.parse(["doctor"]), .doctor)
        XCTAssertEqual(try CellarCommandParser.parse(["init", "zsh"]), .initZsh)
        XCTAssertEqual(try CellarCommandParser.parse(["completions", "zsh"]), .completionsZsh)
        XCTAssertEqual(try CellarCommandParser.parse(["teardown"]), .teardown(purge: false, confirmed: false))
    }

    func testRejectsMalformedSimpleCommandsAndConflictingFilters() {
        XCTAssertThrowsError(try CellarCommandParser.parse(["unknown-command"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["notice", "extra"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["explain"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["init", "fish"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["completions", "bash"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["report", "--formulae", "--casks"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["setup", "--history-file"]))
        XCTAssertThrowsError(try CellarCommandParser.parse(["teardown", "--unknown"]))
    }
}
