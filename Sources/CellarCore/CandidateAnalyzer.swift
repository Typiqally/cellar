import Foundation

public enum CandidateState: String, Codable, Sendable {
    case candidate
    case recent
    case observing
    case protected
    case unknown
}

public enum CandidateBlocker: String, Codable, Sendable {
    case dependencyOnly = "dependency-only"
    case hasDependents = "has-dependents"
    case pinned
    case runningService = "running-service"
    case ignored
    case unsupportedSignal = "unsupported-signal"
}

public struct CandidateAssessment: Equatable, Sendable {
    public let state: CandidateState
    public let inactiveDays: Int?
    public let blockers: [CandidateBlocker]
}

public struct CandidateAnalyzer: Sendable {
    public let staleDays: Int

    public init(staleDays: Int) {
        self.staleDays = staleDays
    }

    public func assess(_ package: TrackedPackage, now: Date) -> CandidateAssessment {
        guard package.supportsUsageSignal else {
            return CandidateAssessment(state: .unknown, inactiveDays: nil, blockers: [.unsupportedSignal])
        }

        let blockers = blockers(for: package)
        guard blockers.isEmpty else {
            return CandidateAssessment(state: .protected, inactiveDays: inactiveDays(for: package, now: now), blockers: blockers)
        }

        let inactiveDays = inactiveDays(for: package, now: now) ?? 0
        if package.lastUsedAt == nil, inactiveDays < staleDays {
            return CandidateAssessment(state: .observing, inactiveDays: inactiveDays, blockers: [])
        }
        return CandidateAssessment(
            state: inactiveDays >= staleDays ? .candidate : .recent,
            inactiveDays: inactiveDays,
            blockers: []
        )
    }

    private func blockers(for package: TrackedPackage) -> [CandidateBlocker] {
        var result: [CandidateBlocker] = []
        if !package.installedOnRequest { result.append(.dependencyOnly) }
        if !package.isLeaf { result.append(.hasDependents) }
        if package.isPinned { result.append(.pinned) }
        if package.isRunningService { result.append(.runningService) }
        if package.isIgnored { result.append(.ignored) }
        return result
    }

    private func inactiveDays(for package: TrackedPackage, now: Date) -> Int? {
        let reference = package.lastUsedAt ?? package.observedSince
        guard reference <= now else { return 0 }
        return Int(now.timeIntervalSince(reference) / 86_400)
    }
}
