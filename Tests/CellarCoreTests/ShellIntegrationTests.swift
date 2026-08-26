import XCTest
@testable import CellarCore

final class ShellIntegrationTests: XCTestCase {
    func testZshIntegrationIsIdempotentPrivateAndProcessFreePerCommand() {
        let script = ShellIntegration.zshInit(executableName: "cellar")

        XCTAssertTrue(script.contains("add-zsh-hook preexec _cellar_preexec"))
        XCTAssertTrue(script.contains("command cellar notice"))
        XCTAssertTrue(script.contains("${(z)1}"))
        XCTAssertTrue(script.contains("events.log"))
        XCTAssertFalse(script.contains("eval $1"))
        XCTAssertFalse(script.contains("cellar record"))
    }
}
