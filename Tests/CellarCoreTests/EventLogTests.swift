import XCTest
@testable import CellarCore

final class EventLogTests: XCTestCase {
    func testConsumeRecordsValidEventsAndSkipsMalformedLines() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CellarStore(directory: directory)
        try store.replaceInventory([Self.package])
        let eventURL = directory.appending(path: "events.log")
        try "1\t200\tformula\tjq\nbad\n1\t150\tformula\tjq\n".write(to: eventURL, atomically: true, encoding: .utf8)

        let summary = try UsageEventLog(url: eventURL).consume(into: store)

        XCTAssertEqual(summary.accepted, 2)
        XCTAssertEqual(summary.rejected, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventURL.path))
        XCTAssertEqual(try store.packages().first?.lastUsedAt, Date(timeIntervalSince1970: 200))
    }

    func testMissingLogIsAnEmptySuccessfulConsume() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CellarStore(directory: directory)

        let summary = try UsageEventLog(url: directory.appending(path: "events.log")).consume(into: store)

        XCTAssertEqual(summary, EventLogSummary(accepted: 0, rejected: 0))
    }

    private static let package = TrackedPackage(
        id: "formula:jq",
        name: "jq",
        kind: .formula,
        installedOnRequest: true,
        isLeaf: true,
        isPinned: false,
        isRunningService: false,
        isIgnored: false,
        supportsUsageSignal: true,
        observedSince: Date(timeIntervalSince1970: 100),
        lastUsedAt: nil,
        evidenceSource: nil
    )
}
