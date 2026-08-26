import Foundation

public enum NoticePolicy: String, Codable, CaseIterable, Sendable {
    case daily
    case always
    case changed
    case off
}

public struct CellarConfiguration: Codable, Equatable, Sendable {
    public static let `default` = CellarConfiguration(staleDays: 90, notice: .daily)

    public var staleDays: Int
    public var notice: NoticePolicy

    public init(staleDays: Int, notice: NoticePolicy) {
        self.staleDays = staleDays
        self.notice = notice
    }

    public func validated() throws -> Self {
        guard (1...3_650).contains(staleDays) else {
            throw ConfigurationError.invalidStaleDays(staleDays)
        }
        return self
    }
}

public enum ConfigurationError: LocalizedError, Equatable {
    case invalidStaleDays(Int)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidStaleDays(days):
            "stale-days must be between 1 and 3650 (received \(days))"
        case let .unsupportedVersion(version):
            "unsupported configuration version \(version)"
        }
    }
}

public enum ConfigurationCodec {
    private struct Envelope: Codable {
        let version: Int
        let staleDays: Int
        let notice: NoticePolicy
    }

    public static func encode(_ configuration: CellarConfiguration) throws -> Data {
        let valid = try configuration.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(version: 1, staleDays: valid.staleDays, notice: valid.notice))
    }

    public static func decode(_ data: Data) throws -> CellarConfiguration {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1 else {
            throw ConfigurationError.unsupportedVersion(envelope.version)
        }
        return try CellarConfiguration(staleDays: envelope.staleDays, notice: envelope.notice).validated()
    }
}
