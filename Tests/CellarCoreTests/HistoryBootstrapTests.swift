import XCTest
@testable import CellarCore

final class HistoryBootstrapTests: XCTestCase {
    func testTimestampedHistoryProducesLatestPackageEvidence() {
        let history = """
        : 1690000000:0;jq '.name' input.json
        : 1700000000:1;rg TODO Sources | head
        : 1710000000:0;jq '.version' package.json
        malformed line
        """
        let ownership: [String: PackageOwnership] = [
            "jq": PackageOwnership(kind: .formula, token: "jq"),
            "rg": PackageOwnership(kind: .formula, token: "ripgrep"),
        ]

        let evidence = ZshHistoryBootstrap.latestEvidence(in: history) { ownership[$0] }

        XCTAssertEqual(evidence[PackageOwnership(kind: .formula, token: "jq")], Date(timeIntervalSince1970: 1_710_000_000))
        XCTAssertEqual(evidence[PackageOwnership(kind: .formula, token: "ripgrep")], Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(evidence.count, 2)
    }

    func testHistoryParserUnderstandsPipelinesWithoutEvaluatingInput() {
        let commands = ZshHistoryBootstrap.commandNames(in: "sudo env FOO=bar rg thing | jq . && echo done")

        XCTAssertEqual(commands, ["rg", "jq", "echo"])
    }
}
