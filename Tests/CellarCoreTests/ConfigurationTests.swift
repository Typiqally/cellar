import XCTest
@testable import CellarCore

final class ConfigurationTests: XCTestCase {
    func testDefaultsAreConservativeAndSimple() {
        let configuration = CellarConfiguration.default

        XCTAssertEqual(configuration.staleDays, 90)
        XCTAssertEqual(configuration.notice, .daily)
    }

    func testStaleDaysMustStayWithinDocumentedRange() throws {
        XCTAssertThrowsError(try CellarConfiguration(staleDays: 0, notice: .daily).validated())
        XCTAssertThrowsError(try CellarConfiguration(staleDays: 3_651, notice: .daily).validated())
        XCTAssertEqual(try CellarConfiguration(staleDays: 1, notice: .off).validated().staleDays, 1)
        XCTAssertEqual(try CellarConfiguration(staleDays: 3_650, notice: .always).validated().staleDays, 3_650)
    }

    func testConfigurationRoundTripsAsVersionedJSON() throws {
        let original = CellarConfiguration(staleDays: 120, notice: .changed)

        let data = try ConfigurationCodec.encode(original)
        let decoded = try ConfigurationCodec.decode(data)

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"version\""))
    }
}
