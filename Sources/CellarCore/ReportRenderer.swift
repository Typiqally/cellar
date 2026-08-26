import Foundation

public struct ReportItem: Equatable, Sendable {
    public let package: TrackedPackage
    public let assessment: CandidateAssessment

    public init(package: TrackedPackage, assessment: CandidateAssessment) {
        self.package = package
        self.assessment = assessment
    }
}

public enum ReportRenderer {
    public static func text(_ items: [ReportItem], staleDays: Int) -> String {
        guard !items.isEmpty else { return "No packages have aged past \(staleDays) days.\n" }
        var lines = ["PACKAGE\tKIND\tINACTIVE\tEVIDENCE\tSTATE"]
        for item in items {
            let inactive = item.assessment.inactiveDays.map { "\($0)d" } ?? "unknown"
            let evidence = item.package.evidenceSource?.rawValue ?? "observed"
            lines.append("\(item.package.name)\t\(item.package.kind.rawValue)\t\(inactive)\t\(evidence)\t\(item.assessment.state.rawValue)")
        }
        let candidates = items.filter { $0.assessment.state == .candidate }
        if !candidates.isEmpty {
            lines.append("")
            lines.append("Review only; Cellar never removes packages:")
            for item in candidates {
                let flag = item.package.kind == .cask ? " --cask" : ""
                lines.append("  brew uninstall\(flag) \(shellQuote(item.package.name))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func json(_ items: [ReportItem], staleDays: Int) throws -> Data {
        let packages: [[String: Any]] = items.map { item in
            var value: [String: Any] = [
                "id": item.package.id,
                "name": item.package.name,
                "kind": item.package.kind.rawValue,
                "state": item.assessment.state.rawValue,
                "blockers": item.assessment.blockers.map(\.rawValue),
            ]
            value["inactiveDays"] = item.assessment.inactiveDays ?? NSNull()
            value["lastUsedAt"] = item.package.lastUsedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
            value["evidence"] = item.package.evidenceSource?.rawValue ?? NSNull()
            return value
        }
        return try JSONSerialization.data(
            withJSONObject: ["version": 1, "staleDays": staleDays, "packages": packages],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    public static func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%_+=:,./-"))
        if value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
