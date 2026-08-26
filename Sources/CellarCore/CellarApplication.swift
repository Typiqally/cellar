import Foundation

public enum CellarApplicationError: LocalizedError {
    case packageNotFound(String)
    case historyUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case let .packageNotFound(package): "package not found: \(package)"
        case let .historyUnreadable(path): "could not read zsh history at \(path)"
        }
    }
}

public final class CellarApplication {
    public static let version = "0.1.0"

    private let store: CellarStore
    private let paths: CellarPaths
    private let homebrew: any HomebrewDataSource
    private let caskUsage: any CaskUsageProviding
    private let signalProvider: (any PackageSignalProviding)?
    private let environment: [String: String]
    private let homeDirectory: URL
    private let now: () -> Date
    private let writeOutput: (String) -> Void

    public init(
        store: CellarStore,
        paths: CellarPaths,
        homebrew: any HomebrewDataSource,
        caskUsage: any CaskUsageProviding = LaunchServicesCaskUsageProvider(),
        signalProvider: (any PackageSignalProviding)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: @escaping () -> Date = Date.init,
        writeOutput: @escaping (String) -> Void = { FileHandle.standardOutput.write(Data($0.utf8)) }
    ) {
        self.store = store
        self.paths = paths
        self.homebrew = homebrew
        self.caskUsage = caskUsage
        self.signalProvider = signalProvider
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.now = now
        self.writeOutput = writeOutput
    }

    @discardableResult
    public func run(_ command: CellarCommand) throws -> Int32 {
        switch command {
        case let .setup(options):
            try setup(options)
        case .initZsh:
            writeOutput(ShellIntegration.zshInit() + "\n")
        case .notice:
            try notice()
        case let .report(options):
            try report(options)
        case let .explain(package):
            try explain(package)
        case let .ignore(package):
            try setIgnored(package, ignored: true)
        case let .unignore(package):
            try setIgnored(package, ignored: false)
        case .ignored:
            try listIgnored()
        case let .config(command):
            try configure(command)
        case .status:
            try status()
        case .refresh:
            let summary = try maintain()
            writeOutput("Refreshed \(summary.packageCount) packages.\n")
        case .maintain:
            _ = try maintain()
        case .doctor:
            try doctor()
        case .completionsZsh:
            writeOutput(Self.zshCompletions)
        case let .teardown(purge, confirmed):
            try teardown(purge: purge, confirmed: confirmed)
        case .help:
            writeOutput(Self.help)
        case .version:
            writeOutput("cellar \(Self.version)\n")
        }
        return 0
    }

    private func setup(_ options: SetupOptions) throws {
        if !FileManager.default.fileExists(atPath: store.configurationURL.path) {
            try store.saveConfiguration(.default)
        }
        let summary = try maintain()
        if options.bootstrapHistory {
            try bootstrapHistory(at: options.historyFile)
        }
        if options.startService {
            try homebrew.startService()
        }
        writeOutput("Cellar is tracking \(summary.packageCount) packages.\n\n")
        writeOutput("Add this line to ~/.zshrc:\n\n  eval \"$(cellar init zsh)\"\n")
    }

    private func bootstrapHistory(at explicitPath: String?) throws {
        let historyURL = explicitPath.map { URL(fileURLWithPath: $0) }
            ?? homeDirectory.appending(path: ".zsh_history")
        guard let history = try? String(contentsOf: historyURL, encoding: .utf8) else {
            throw CellarApplicationError.historyUnreadable(historyURL.path)
        }
        let prefix = try homebrew.homebrewPrefix()
        let resolver = ExecutableOwnershipResolver(prefix: prefix, environment: environment)
        let evidence = ZshHistoryBootstrap.latestEvidence(in: history, resolver: resolver.ownership(forCommand:))
        for (ownership, date) in evidence {
            try store.recordUsage(ownership, at: date, source: .history)
        }
        writeOutput("Imported package-only evidence for \(evidence.count) packages.\n")
    }

    private func notice() throws {
        _ = try UsageEventLog(url: paths.events).consume(into: store)
        let configuration = try store.loadConfiguration()
        let candidates = try reportItems(configuration: configuration, showAll: false, kind: nil)
        guard !candidates.isEmpty else { return }
        let signature = candidates.map(\.package.id).sorted().joined(separator: "\n")
        guard try store.claimNotice(policy: configuration.notice, now: now(), signature: signature) else { return }
        let count = candidates.count
        let subject = count == 1 ? "1 package has" : "\(count) packages have"
        writeOutput("Cellar: \(subject) aged past \(configuration.staleDays) days — run 'cellar report'.\n")
    }

    private func report(_ options: ReportOptions) throws {
        _ = try UsageEventLog(url: paths.events).consume(into: store)
        if options.orphans {
            writeOutput(try homebrew.orphanedDependencies())
            return
        }
        let configuration = try store.loadConfiguration()
        let items = try reportItems(configuration: configuration, showAll: options.showAll, kind: options.kind)
        if options.json {
            writeOutput(String(decoding: try ReportRenderer.json(items, staleDays: configuration.staleDays), as: UTF8.self) + "\n")
        } else {
            writeOutput(ReportRenderer.text(items, staleDays: configuration.staleDays))
        }
    }

    private func reportItems(
        configuration: CellarConfiguration,
        showAll: Bool,
        kind: PackageKind?
    ) throws -> [ReportItem] {
        let analyzer = CandidateAnalyzer(staleDays: configuration.staleDays)
        return try store.packages()
            .filter { kind == nil || $0.kind == kind }
            .map { ReportItem(package: $0, assessment: analyzer.assess($0, now: now())) }
            .filter { showAll || $0.assessment.state == .candidate }
            .sorted {
                if $0.assessment.inactiveDays != $1.assessment.inactiveDays {
                    return ($0.assessment.inactiveDays ?? -1) > ($1.assessment.inactiveDays ?? -1)
                }
                return $0.package.name.localizedCaseInsensitiveCompare($1.package.name) == .orderedAscending
            }
    }

    private func explain(_ value: String) throws {
        let package = try findPackage(value)
        let configuration = try store.loadConfiguration()
        let assessment = CandidateAnalyzer(staleDays: configuration.staleDays).assess(package, now: now())
        writeOutput("\(package.name) (\(package.kind.rawValue))\n")
        writeOutput("State: \(assessment.state.rawValue)\n")
        writeOutput("Inactive: \(assessment.inactiveDays.map { "\($0) days" } ?? "unknown")\n")
        writeOutput("Evidence: \(package.evidenceSource?.rawValue ?? "none")\n")
        if !assessment.blockers.isEmpty {
            writeOutput("Protected by: \(assessment.blockers.map(\.rawValue).joined(separator: ", "))\n")
        }
    }

    private func setIgnored(_ value: String, ignored: Bool) throws {
        let package = try findPackage(value)
        try store.setIgnored(packageID: package.id, ignored: ignored)
        writeOutput("\(package.name) is \(ignored ? "ignored" : "tracked again").\n")
    }

    private func listIgnored() throws {
        let ignored = try store.packages().filter(\.isIgnored)
        if ignored.isEmpty {
            writeOutput("No ignored packages.\n")
        } else {
            writeOutput(ignored.map(\.name).joined(separator: "\n") + "\n")
        }
    }

    private func configure(_ command: ConfigurationCommand) throws {
        var configuration = try store.loadConfiguration()
        switch command {
        case .show:
            break
        case let .setStaleDays(days):
            configuration.staleDays = days
            try store.saveConfiguration(try configuration.validated())
        case let .setNotice(policy):
            configuration.notice = policy
            try store.saveConfiguration(configuration)
        case let .reset(key):
            if key == "stale-days" || key == "all" { configuration.staleDays = CellarConfiguration.default.staleDays }
            if key == "notice" || key == "all" { configuration.notice = CellarConfiguration.default.notice }
            try store.saveConfiguration(configuration)
        }
        writeOutput("stale-days = \(configuration.staleDays)\nnotice = \(configuration.notice.rawValue)\n")
    }

    private func status() throws {
        let configuration = try store.loadConfiguration()
        let packages = try store.packages()
        let candidates = packages.filter { CandidateAnalyzer(staleDays: configuration.staleDays).assess($0, now: now()).state == .candidate }
        writeOutput("Tracking \(packages.count) packages; \(candidates.count) aged candidates.\n")
        if let lastRefresh = try store.metadata("last-refresh").flatMap(TimeInterval.init) {
            writeOutput("Last refresh: \(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: lastRefresh)))\n")
        } else {
            writeOutput("Last refresh: never\n")
        }
    }

    private func maintain() throws -> MaintenanceSummary {
        try MaintenanceService(
            store: store,
            eventLog: UsageEventLog(url: paths.events),
            homebrew: homebrew,
            caskUsage: caskUsage,
            signalProvider: signalProvider,
            now: now
        ).run()
    }

    private func doctor() throws {
        _ = try homebrew.homebrewPrefix()
        _ = try store.loadConfiguration()
        writeOutput("✓ Homebrew available\n✓ State readable and private\n✓ Configuration valid\n")
    }

    private func teardown(purge: Bool, confirmed: Bool) throws {
        try homebrew.stopService()
        if purge {
            guard confirmed else { throw CommandParserError.unsafePurge }
            try store.purge()
            writeOutput("Cellar service and local state removed.\n")
        } else {
            writeOutput("Cellar service stopped; local state preserved.\n")
        }
        writeOutput("Remove eval \"$(cellar init zsh)\" from ~/.zshrc if present.\n")
    }

    private func findPackage(_ value: String) throws -> TrackedPackage {
        guard let package = try store.packages().first(where: { $0.id == value || $0.name == value }) else {
            throw CellarApplicationError.packageNotFound(value)
        }
        return package
    }

    public static let help = """
    Cellar tracks how long Homebrew packages have gone unused.

    Usage: cellar <command> [options]

      setup [--bootstrap-history] [--history-file PATH] [--no-service]
      init zsh                 Print lightweight zsh integration
      notice                   Print a throttled shell-start reminder
      report [--all] [--formulae|--casks] [--json|--orphans]
      explain PACKAGE          Explain a package's classification
      ignore PACKAGE           Exclude a package from recommendations
      unignore PACKAGE         Resume recommendations for a package
      ignore --list            List ignored packages
      config                   Show configuration
      config set stale-days N
      config set notice daily|always|changed|off
      config reset stale-days|notice|all
      status                   Show tracking health
      refresh                  Refresh now and print a summary
      doctor                   Check the installation
      completions zsh          Print zsh completions
      teardown [--purge --yes]
    """ + "\n"

    public static let zshCompletions = """
    #compdef cellar
    _arguments '1:command:(setup init notice report explain ignore unignore config status refresh doctor completions teardown help version)'
    """ + "\n"
}

struct ExecutableOwnershipResolver {
    let pathResolver: HomebrewPathResolver
    let searchPaths: [String]

    init(prefix: String, environment: [String: String]) {
        pathResolver = HomebrewPathResolver(prefix: prefix)
        searchPaths = (environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)
    }

    func ownership(forCommand command: String) -> PackageOwnership? {
        guard PackageToken.isValid(command) else { return nil }
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appending(path: command)
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            return pathResolver.ownership(ofCanonicalPath: candidate.resolvingSymlinksInPath().path)
        }
        return nil
    }
}
