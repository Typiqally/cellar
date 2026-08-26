import Foundation

public enum NoticeGate {
    public static func shouldDisplay(
        policy: NoticePolicy,
        now: Date,
        lastShownAt: Date?,
        signature: String,
        lastSignature: String?,
        calendar: Calendar = .current
    ) -> Bool {
        switch policy {
        case .off:
            return false
        case .always:
            return true
        case .changed:
            return signature != lastSignature
        case .daily:
            guard let lastShownAt else { return true }
            return !calendar.isDate(lastShownAt, inSameDayAs: now)
        }
    }
}
