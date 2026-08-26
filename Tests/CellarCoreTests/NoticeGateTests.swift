import XCTest
@testable import CellarCore

final class NoticeGateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDailyNoticeAppearsOnlyOncePerDay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-86_400)

        XCTAssertTrue(NoticeGate.shouldDisplay(policy: .daily, now: now, lastShownAt: yesterday, signature: "a", lastSignature: "a", calendar: calendar))
        XCTAssertFalse(NoticeGate.shouldDisplay(policy: .daily, now: now, lastShownAt: now.addingTimeInterval(-60), signature: "a", lastSignature: "a", calendar: calendar))
    }

    func testChangedNoticeUsesCandidateSignature() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(NoticeGate.shouldDisplay(policy: .changed, now: now, lastShownAt: now, signature: "new", lastSignature: "old", calendar: calendar))
        XCTAssertFalse(NoticeGate.shouldDisplay(policy: .changed, now: now, lastShownAt: nil, signature: "same", lastSignature: "same", calendar: calendar))
    }

    func testAlwaysAndOffPolicies() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(NoticeGate.shouldDisplay(policy: .always, now: now, lastShownAt: now, signature: "a", lastSignature: "a", calendar: calendar))
        XCTAssertFalse(NoticeGate.shouldDisplay(policy: .off, now: now, lastShownAt: nil, signature: "a", lastSignature: nil, calendar: calendar))
    }
}
