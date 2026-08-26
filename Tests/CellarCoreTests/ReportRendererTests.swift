import XCTest
@testable import CellarCore

final class ReportRendererTests: XCTestCase {
    func testTextReportIncludesEvidenceAndSafeRemovalCommand() {
        let item = ReportItem(
            package: Self.package,
            assessment: CandidateAssessment(state: .candidate, inactiveDays: 123, blockers: [])
        )

        let output = ReportRenderer.text([item], staleDays: 90)

        XCTAssertTrue(output.contains("ripgrep"))
        XCTAssertTrue(output.contains("123d"))
        XCTAssertTrue(output.contains("shell"))
        XCTAssertTrue(output.contains("brew uninstall ripgrep"))
        XCTAssertFalse(output.contains("Executing"))
    }

    func testJSONReportHasVersionedStableShape() throws {
        let item = ReportItem(
            package: Self.package,
            assessment: CandidateAssessment(state: .candidate, inactiveDays: 123, blockers: [])
        )

        let data = try ReportRenderer.json([item], staleDays: 90)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["staleDays"] as? Int, 90)
        XCTAssertEqual((object["packages"] as? [[String: Any]])?.first?["id"] as? String, "formula:ripgrep")
    }

    func testCaskRemovalCommandUsesCaskFlagAndShellQuotesToken() {
        var package = Self.package
        package.id = "cask:odd package"
        package.name = "odd package"
        package.kind = .cask
        let item = ReportItem(package: package, assessment: CandidateAssessment(state: .candidate, inactiveDays: 100, blockers: []))

        let output = ReportRenderer.text([item], staleDays: 90)

        XCTAssertTrue(output.contains("brew uninstall --cask 'odd package'"))
    }

    private static let package = TrackedPackage(
        id: "formula:ripgrep",
        name: "ripgrep",
        kind: .formula,
        installedOnRequest: true,
        isLeaf: true,
        isPinned: false,
        isRunningService: false,
        isIgnored: false,
        supportsUsageSignal: true,
        observedSince: Date(timeIntervalSince1970: 100),
        lastUsedAt: Date(timeIntervalSince1970: 200),
        evidenceSource: .shell
    )
}
