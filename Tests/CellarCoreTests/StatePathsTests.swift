import XCTest
@testable import CellarCore

final class StatePathsTests: XCTestCase {
    func testEnvironmentOverrideWins() {
        let paths = CellarPaths(environment: ["CELLAR_STATE_DIR": "/tmp/cellar-state"], homeDirectory: URL(fileURLWithPath: "/Users/test"))

        XCTAssertEqual(paths.stateDirectory.path, "/tmp/cellar-state")
        XCTAssertEqual(paths.events.path, "/tmp/cellar-state/events.log")
    }

    func testDefaultUsesNativeApplicationSupportDirectory() {
        let paths = CellarPaths(environment: [:], homeDirectory: URL(fileURLWithPath: "/Users/test"))

        XCTAssertEqual(paths.stateDirectory.path, "/Users/test/Library/Application Support/Cellar")
    }
}
