import Foundation

public struct EventLogSummary: Equatable, Sendable {
    public let accepted: Int
    public let rejected: Int

    public init(accepted: Int, rejected: Int) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

public struct UsageEventLog: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func consume(into store: CellarStore) throws -> EventLogSummary {
        let batchURL = url.deletingLastPathComponent().appending(path: ".events-\(UUID().uuidString).processing")
        do {
            try FileManager.default.moveItem(at: url, to: batchURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return EventLogSummary(accepted: 0, rejected: 0)
        }

        do {
            let contents = try String(contentsOf: batchURL, encoding: .utf8)
            var accepted = 0
            var rejected = 0
            for line in contents.split(whereSeparator: \.isNewline) {
                do {
                    let event = try UsageEventCodec.decode(String(line))
                    try store.recordUsage(event.ownership, at: event.timestamp, source: .shell)
                    accepted += 1
                } catch {
                    rejected += 1
                }
            }
            try FileManager.default.removeItem(at: batchURL)
            return EventLogSummary(accepted: accepted, rejected: rejected)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.moveItem(at: batchURL, to: url)
            }
            throw error
        }
    }
}
