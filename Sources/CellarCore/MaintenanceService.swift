import CoreServices
import Foundation

public protocol HomebrewDataSource {
    func installedInventory() throws -> Data
    func serviceInventory() throws -> Data
    func startService() throws
    func stopService() throws
    func orphanedDependencies() throws -> String
}

public protocol CaskUsageProviding {
    func lastUsedDate(forAppAt path: String) -> Date?
}

public struct LaunchServicesCaskUsageProvider: CaskUsageProviding {
    public init() {}

    public func lastUsedDate(forAppAt path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        return value as? Date
    }
}

public struct MaintenanceSummary: Equatable, Sendable {
    public let packageCount: Int
    public let acceptedEvents: Int
    public let rejectedEvents: Int
}

public struct MaintenanceService {
    private let store: CellarStore
    private let eventLog: UsageEventLog
    private let homebrew: any HomebrewDataSource
    private let caskUsage: any CaskUsageProviding
    private let now: () -> Date

    public init(
        store: CellarStore,
        eventLog: UsageEventLog,
        homebrew: any HomebrewDataSource,
        caskUsage: any CaskUsageProviding = LaunchServicesCaskUsageProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.eventLog = eventLog
        self.homebrew = homebrew
        self.caskUsage = caskUsage
        self.now = now
    }

    public func run() throws -> MaintenanceSummary {
        let refreshDate = now()
        let inventory = try HomebrewInventoryDecoder.decode(homebrew.installedInventory())
        let runningServices = try decodeRunningServices(homebrew.serviceInventory())
        let trackedPackages = inventory.packages.map { package in
            TrackedPackage(
                id: package.id,
                name: package.name,
                kind: package.kind,
                installedOnRequest: package.installedOnRequest,
                isLeaf: package.isLeaf,
                isPinned: package.isPinned,
                isRunningService: runningServices.contains(package.name) || runningServices.contains(package.id),
                isIgnored: false,
                supportsUsageSignal: package.supportsUsageSignal,
                observedSince: refreshDate,
                lastUsedAt: nil,
                evidenceSource: nil
            )
        }
        try store.replaceInventory(trackedPackages)
        let eventSummary = try eventLog.consume(into: store)

        for package in inventory.packages where package.kind == .cask {
            let dates = package.appPaths.compactMap(caskUsage.lastUsedDate(forAppAt:))
            if let latest = dates.max() {
                let token = package.id.dropFirst("cask:".count)
                try store.recordUsage(PackageOwnership(kind: .cask, token: String(token)), at: latest, source: .launchServices)
            }
        }
        try store.setMetadata(String(Int(refreshDate.timeIntervalSince1970)), for: "last-refresh")
        return MaintenanceSummary(
            packageCount: trackedPackages.count,
            acceptedEvents: eventSummary.accepted,
            rejectedEvents: eventSummary.rejected
        )
    }

    private func decodeRunningServices(_ data: Data) throws -> Set<String> {
        guard let services = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return Set(services.compactMap { service in
            guard let name = service["name"] as? String,
                  let status = service["status"] as? String,
                  status != "none", status != "stopped" else { return nil }
            return name
        })
    }
}
