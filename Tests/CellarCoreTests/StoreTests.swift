import XCTest
@testable import CellarCore

final class StoreTests: XCTestCase {
    func testStorePersistsConfigurationPackagesAndLatestEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CellarStore(directory: directory)
        let package = TrackedPackage(
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

        try store.saveConfiguration(CellarConfiguration(staleDays: 120, notice: .off))
        try store.replaceInventory([package])
        try store.recordUsage(PackageOwnership(kind: .formula, token: "jq"), at: Date(timeIntervalSince1970: 200), source: .shell)
        try store.recordUsage(PackageOwnership(kind: .formula, token: "jq"), at: Date(timeIntervalSince1970: 150), source: .history)

        XCTAssertEqual(try store.loadConfiguration(), CellarConfiguration(staleDays: 120, notice: .off))
        let stored = try XCTUnwrap(store.packages().first)
        XCTAssertEqual(stored.lastUsedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(stored.evidenceSource, .shell)
    }

    func testStoreUsesPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try CellarStore(directory: directory)

        let directoryMode = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: directory.path))[.posixPermissions] as? NSNumber
        ).intValue
        let database = directory.appending(path: "state.sqlite3")
        let fileMode = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: database.path))[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(fileMode & 0o777, 0o600)
    }

    func testNoticeClaimIsAtomicForDailyPolicy() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CellarStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        XCTAssertTrue(try store.claimNotice(policy: .daily, now: now, signature: "formula:jq", calendar: calendar))
        XCTAssertFalse(try store.claimNotice(policy: .daily, now: now.addingTimeInterval(60), signature: "formula:jq", calendar: calendar))
        XCTAssertTrue(try store.claimNotice(policy: .daily, now: now.addingTimeInterval(86_400), signature: "formula:jq", calendar: calendar))
    }

    func testUsageBeforeInventoryRefreshIsAppliedWhenPackageAppears() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CellarStore(directory: directory)
        let usedAt = Date(timeIntervalSince1970: 500)

        try store.recordUsage(
            PackageOwnership(kind: .formula, token: "jq"),
            at: usedAt,
            source: .shell
        )
        try store.replaceInventory([TrackedPackage(
            id: "formula:jq",
            name: "jq",
            kind: .formula,
            installedOnRequest: true,
            isLeaf: true,
            isPinned: false,
            isRunningService: false,
            isIgnored: false,
            supportsUsageSignal: true,
            observedSince: Date(timeIntervalSince1970: 600),
            lastUsedAt: nil,
            evidenceSource: nil
        )])

        let package = try XCTUnwrap(store.packages().first)
        XCTAssertEqual(package.lastUsedAt, usedAt)
        XCTAssertEqual(package.evidenceSource, .shell)
    }
}
