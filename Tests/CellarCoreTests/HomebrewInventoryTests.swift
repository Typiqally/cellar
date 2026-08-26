import XCTest
@testable import CellarCore

final class HomebrewInventoryTests: XCTestCase {
    func testInventoryDecodesFormulaeCasksDependenciesAndAppTargets() throws {
        let data = Data(Self.fixture.utf8)

        let inventory = try HomebrewInventoryDecoder.decode(data)

        let jq = try XCTUnwrap(inventory.packages.first { $0.id == "formula:jq" })
        XCTAssertTrue(jq.installedOnRequest)
        XCTAssertEqual(jq.dependencies, ["formula:oniguruma"])

        let vscode = try XCTUnwrap(inventory.packages.first { $0.id == "cask:visual-studio-code" })
        XCTAssertEqual(vscode.appPaths, ["/Applications/Visual Studio Code.app"])
        XCTAssertTrue(vscode.supportsUsageSignal)

        let oniguruma = try XCTUnwrap(inventory.packages.first { $0.id == "formula:oniguruma" })
        XCTAssertFalse(oniguruma.isLeaf)
    }

    private static let fixture = #"""
    {
      "formulae": [
        {
          "name": "jq",
          "full_name": "jq",
          "pinned": false,
          "installed": [{
            "time": 1600000000,
            "installed_on_request": true,
            "runtime_dependencies": [{"full_name": "oniguruma"}]
          }],
          "service": null
        },
        {
          "name": "oniguruma",
          "full_name": "oniguruma",
          "pinned": false,
          "installed": [{
            "time": 1600000000,
            "installed_on_request": false,
            "runtime_dependencies": []
          }],
          "service": null
        }
      ],
      "casks": [{
        "token": "visual-studio-code",
        "full_token": "visual-studio-code",
        "installed": "1.0",
        "installed_time": 1600000000,
        "pinned": false,
        "depends_on": {},
        "artifacts": [{
          "app": ["Visual Studio Code.app"],
          "target": ["/Applications/Visual Studio Code.app"]
        }]
      }]
    }
    """#
}
