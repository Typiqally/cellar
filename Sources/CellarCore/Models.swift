import Foundation

public enum PackageKind: String, Codable, CaseIterable, Sendable {
    case formula
    case cask
}

public enum EvidenceSource: String, Codable, Sendable {
    case shell
    case history
    case launchServices = "launch-services"
    case endpointSecurity = "endpoint-security"
}

public struct PackageOwnership: Hashable, Codable, Sendable {
    public let kind: PackageKind
    public let token: String

    public init(kind: PackageKind, token: String) {
        self.kind = kind
        self.token = token
    }

    public var id: String { "\(kind.rawValue):\(token)" }
}

public struct TrackedPackage: Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var kind: PackageKind
    public var installedOnRequest: Bool
    public var isLeaf: Bool
    public var isPinned: Bool
    public var isRunningService: Bool
    public var isIgnored: Bool
    public var supportsUsageSignal: Bool
    public var observedSince: Date
    public var lastUsedAt: Date?
    public var evidenceSource: EvidenceSource?

    public init(
        id: String,
        name: String,
        kind: PackageKind,
        installedOnRequest: Bool,
        isLeaf: Bool,
        isPinned: Bool,
        isRunningService: Bool,
        isIgnored: Bool,
        supportsUsageSignal: Bool,
        observedSince: Date,
        lastUsedAt: Date?,
        evidenceSource: EvidenceSource?
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.installedOnRequest = installedOnRequest
        self.isLeaf = isLeaf
        self.isPinned = isPinned
        self.isRunningService = isRunningService
        self.isIgnored = isIgnored
        self.supportsUsageSignal = supportsUsageSignal
        self.observedSince = observedSince
        self.lastUsedAt = lastUsedAt
        self.evidenceSource = evidenceSource
    }
}

public struct InventoryPackage: Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: PackageKind
    public var installedOnRequest: Bool
    public var isLeaf: Bool
    public var isPinned: Bool
    public var supportsUsageSignal: Bool
    public var installedAt: Date?
    public var dependencies: [String]
    public var appPaths: [String]
}

public struct HomebrewInventory: Equatable, Sendable {
    public var packages: [InventoryPackage]
}
