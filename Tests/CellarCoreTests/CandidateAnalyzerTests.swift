import XCTest
@testable import CellarCore

final class CandidateAnalyzerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testOldUnusedLeafBecomesCandidate() {
        let package = makePackage(lastUsedDaysAgo: 120)

        let assessment = CandidateAnalyzer(staleDays: 90).assess(package, now: now)

        XCTAssertEqual(assessment.state, .candidate)
        XCTAssertEqual(assessment.inactiveDays, 120)
        XCTAssertTrue(assessment.blockers.isEmpty)
    }

    func testRecentPackageIsNotCandidate() {
        let assessment = CandidateAnalyzer(staleDays: 90).assess(makePackage(lastUsedDaysAgo: 10), now: now)

        XCTAssertEqual(assessment.state, .recent)
    }

    func testUnseenPackageRequiresFullObservationWindow() {
        let package = makePackage(lastUsedDaysAgo: nil, observedDaysAgo: 30)

        let assessment = CandidateAnalyzer(staleDays: 90).assess(package, now: now)

        XCTAssertEqual(assessment.state, .observing)
    }

    func testUnseenPackageCanBecomeCandidateAfterObservationWindow() {
        let package = makePackage(lastUsedDaysAgo: nil, observedDaysAgo: 100)

        let assessment = CandidateAnalyzer(staleDays: 90).assess(package, now: now)

        XCTAssertEqual(assessment.state, .candidate)
        XCTAssertEqual(assessment.inactiveDays, 100)
    }

    func testSafetyBlockersProtectPackage() {
        let scenarios: [(TrackedPackage) -> TrackedPackage] = [
            { $0.setting(\.installedOnRequest, to: false) },
            { $0.setting(\.isLeaf, to: false) },
            { $0.setting(\.isPinned, to: true) },
            { $0.setting(\.isRunningService, to: true) },
            { $0.setting(\.isIgnored, to: true) },
        ]

        for transform in scenarios {
            let assessment = CandidateAnalyzer(staleDays: 90).assess(transform(makePackage(lastUsedDaysAgo: 120)), now: now)
            XCTAssertEqual(assessment.state, .protected)
            XCTAssertFalse(assessment.blockers.isEmpty)
        }
    }

    func testUnsupportedPackageRemainsUnknown() {
        let package = makePackage(lastUsedDaysAgo: 120).setting(\.supportsUsageSignal, to: false)

        XCTAssertEqual(CandidateAnalyzer(staleDays: 90).assess(package, now: now).state, .unknown)
    }

    private func makePackage(lastUsedDaysAgo: Int?, observedDaysAgo: Int = 200) -> TrackedPackage {
        TrackedPackage(
            id: "formula:ripgrep",
            name: "ripgrep",
            kind: .formula,
            installedOnRequest: true,
            isLeaf: true,
            isPinned: false,
            isRunningService: false,
            isIgnored: false,
            supportsUsageSignal: true,
            observedSince: now.addingTimeInterval(TimeInterval(-observedDaysAgo * 86_400)),
            lastUsedAt: lastUsedDaysAgo.map { now.addingTimeInterval(TimeInterval(-$0 * 86_400)) },
            evidenceSource: lastUsedDaysAgo == nil ? nil : .shell
        )
    }
}

private extension TrackedPackage {
    func setting<Value>(_ keyPath: WritableKeyPath<Self, Value>, to value: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}
