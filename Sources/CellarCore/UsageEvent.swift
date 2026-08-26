import Foundation

public struct UsageEvent: Equatable, Sendable {
    public let timestamp: Date
    public let ownership: PackageOwnership

    public init(timestamp: Date, ownership: PackageOwnership) {
        self.timestamp = timestamp
        self.ownership = ownership
    }
}

public enum UsageEventError: LocalizedError {
    case malformed
    case unsupportedVersion
    case invalidToken

    public var errorDescription: String? {
        switch self {
        case .malformed: "malformed usage event"
        case .unsupportedVersion: "unsupported usage event version"
        case .invalidToken: "invalid Homebrew package token"
        }
    }
}

public enum UsageEventCodec {
    public static func encode(_ event: UsageEvent) -> String {
        let seconds = Int(event.timestamp.timeIntervalSince1970)
        return "1\t\(seconds)\t\(event.ownership.kind.rawValue)\t\(event.ownership.token)"
    }

    public static func decode(_ line: String) throws -> UsageEvent {
        guard !line.contains("\n"), !line.contains("\r") else { throw UsageEventError.malformed }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 4, let version = Int(fields[0]), let seconds = TimeInterval(fields[1]) else {
            throw UsageEventError.malformed
        }
        guard version == 1 else { throw UsageEventError.unsupportedVersion }
        guard let kind = PackageKind(rawValue: String(fields[2])) else { throw UsageEventError.malformed }
        let token = String(fields[3])
        guard PackageToken.isValid(token) else { throw UsageEventError.invalidToken }
        return UsageEvent(timestamp: Date(timeIntervalSince1970: seconds), ownership: PackageOwnership(kind: kind, token: token))
    }
}

enum PackageToken {
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@+_.-"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public struct HomebrewPathResolver: Sendable {
    private let prefix: String

    public init(prefix: String) {
        self.prefix = URL(fileURLWithPath: prefix).standardizedFileURL.path
    }

    public func ownership(ofCanonicalPath path: String) -> PackageOwnership? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized == path || URL(fileURLWithPath: path).path == standardized else { return nil }
        return ownership(in: standardized, directory: "Cellar", kind: .formula)
            ?? ownership(in: standardized, directory: "Caskroom", kind: .cask)
    }

    private func ownership(in path: String, directory: String, kind: PackageKind) -> PackageOwnership? {
        let root = "\(prefix)/\(directory)/"
        guard path.hasPrefix(root) else { return nil }
        let remainder = path.dropFirst(root.count)
        guard let token = remainder.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init),
              PackageToken.isValid(token) else { return nil }
        return PackageOwnership(kind: kind, token: token)
    }
}
