import XCTest
@testable import CellarCore

final class UsageEventTests: XCTestCase {
    func testEventRoundTripsWithoutCommandText() throws {
        let event = UsageEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            ownership: PackageOwnership(kind: .formula, token: "ripgrep")
        )

        let line = UsageEventCodec.encode(event)
        let decoded = try UsageEventCodec.decode(line)

        XCTAssertEqual(decoded, event)
        XCTAssertEqual(line, "1\t1700000000\tformula\tripgrep")
    }

    func testEventRejectsInjectedOrMalformedTokens() {
        XCTAssertThrowsError(try UsageEventCodec.decode("1\t1700000000\tformula\tjq\nother"))
        XCTAssertThrowsError(try UsageEventCodec.decode("1\t1700000000\tformula\t../../etc/passwd"))
        XCTAssertThrowsError(try UsageEventCodec.decode("2\t1700000000\tformula\tjq"))
    }

    func testPathResolverRecognizesCellarAndCaskroom() {
        let resolver = HomebrewPathResolver(prefix: "/opt/homebrew")

        XCTAssertEqual(
            resolver.ownership(ofCanonicalPath: "/opt/homebrew/Cellar/jq/1.7.1/bin/jq"),
            PackageOwnership(kind: .formula, token: "jq")
        )
        XCTAssertEqual(
            resolver.ownership(ofCanonicalPath: "/opt/homebrew/Caskroom/docker/4.42/Docker.app/Contents/MacOS/Docker"),
            PackageOwnership(kind: .cask, token: "docker")
        )
        XCTAssertNil(resolver.ownership(ofCanonicalPath: "/usr/bin/git"))
        XCTAssertNil(resolver.ownership(ofCanonicalPath: "/opt/homebrew/Cellar/../etc/passwd"))
    }
}
