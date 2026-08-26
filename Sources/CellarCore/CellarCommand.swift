import Foundation

public struct ReportOptions: Equatable, Sendable {
    public var showAll: Bool
    public var kind: PackageKind?
    public var json: Bool
    public var orphans: Bool

    public init(showAll: Bool = false, kind: PackageKind? = nil, json: Bool = false, orphans: Bool = false) {
        self.showAll = showAll
        self.kind = kind
        self.json = json
        self.orphans = orphans
    }
}

public struct SetupOptions: Equatable, Sendable {
    public var bootstrapHistory: Bool
    public var historyFile: String?
    public var startService: Bool

    public init(bootstrapHistory: Bool = false, historyFile: String? = nil, startService: Bool = true) {
        self.bootstrapHistory = bootstrapHistory
        self.historyFile = historyFile
        self.startService = startService
    }
}

public enum ConfigurationCommand: Equatable, Sendable {
    case show
    case setStaleDays(Int)
    case setNotice(NoticePolicy)
    case reset(String)
}

public enum CellarCommand: Equatable, Sendable {
    case setup(SetupOptions)
    case initZsh
    case notice
    case report(ReportOptions)
    case explain(String)
    case ignore(String)
    case unignore(String)
    case ignored
    case config(ConfigurationCommand)
    case status
    case refresh
    case maintain
    case doctor
    case completionsZsh
    case teardown(purge: Bool, confirmed: Bool)
    case help
    case version
}

public enum CommandParserError: LocalizedError, Equatable {
    case unknownCommand(String)
    case unknownOption(String)
    case missingValue(String)
    case invalidValue(String)
    case unsafePurge

    public var errorDescription: String? {
        switch self {
        case let .unknownCommand(command): "unknown command: \(command)"
        case let .unknownOption(option): "unknown option: \(option)"
        case let .missingValue(name): "missing value for \(name)"
        case let .invalidValue(value): "invalid value: \(value)"
        case .unsafePurge: "--purge also requires --yes"
        }
    }
}

public enum CellarCommandParser {
    public static func parse(_ arguments: [String]) throws -> CellarCommand {
        guard let command = arguments.first else { return .help }
        let remainder = Array(arguments.dropFirst())
        switch command {
        case "help", "--help", "-h": return .help
        case "version", "--version", "-v": return .version
        case "setup": return .setup(try parseSetup(remainder))
        case "init":
            guard remainder == ["zsh"] else { throw CommandParserError.invalidValue(remainder.joined(separator: " ")) }
            return .initZsh
        case "notice": return try noArguments(.notice, remainder)
        case "report": return .report(try parseReport(remainder))
        case "explain": return .explain(try oneValue("package", remainder))
        case "ignore":
            if remainder == ["--list"] { return .ignored }
            return .ignore(try oneValue("package", remainder))
        case "unignore": return .unignore(try oneValue("package", remainder))
        case "config": return .config(try parseConfiguration(remainder))
        case "status": return try noArguments(.status, remainder)
        case "refresh": return try noArguments(.refresh, remainder)
        case "maintain": return try noArguments(.maintain, remainder)
        case "doctor": return try noArguments(.doctor, remainder)
        case "completions":
            guard remainder == ["zsh"] else { throw CommandParserError.invalidValue(remainder.joined(separator: " ")) }
            return .completionsZsh
        case "teardown": return try parseTeardown(remainder)
        default: throw CommandParserError.unknownCommand(command)
        }
    }

    private static func parseSetup(_ arguments: [String]) throws -> SetupOptions {
        var options = SetupOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--bootstrap-history": options.bootstrapHistory = true
            case "--no-service": options.startService = false
            case "--history-file":
                index += 1
                guard index < arguments.count else { throw CommandParserError.missingValue("--history-file") }
                options.historyFile = arguments[index]
            default: throw CommandParserError.unknownOption(arguments[index])
            }
            index += 1
        }
        if options.historyFile != nil { options.bootstrapHistory = true }
        return options
    }

    private static func parseReport(_ arguments: [String]) throws -> ReportOptions {
        var options = ReportOptions()
        for argument in arguments {
            switch argument {
            case "--all": options.showAll = true
            case "--formulae":
                guard options.kind == nil else { throw CommandParserError.invalidValue("package-kind filters are mutually exclusive") }
                options.kind = .formula
            case "--casks":
                guard options.kind == nil else { throw CommandParserError.invalidValue("package-kind filters are mutually exclusive") }
                options.kind = .cask
            case "--json": options.json = true
            case "--orphans": options.orphans = true
            default: throw CommandParserError.unknownOption(argument)
            }
        }
        return options
    }

    private static func parseConfiguration(_ arguments: [String]) throws -> ConfigurationCommand {
        if arguments.isEmpty { return .show }
        if arguments.count == 3, arguments[0] == "set", arguments[1] == "stale-days",
           let days = Int(arguments[2]), (1...3_650).contains(days) {
            return .setStaleDays(days)
        }
        if arguments.count == 3, arguments[0] == "set", arguments[1] == "notice",
           let policy = NoticePolicy(rawValue: arguments[2]) {
            return .setNotice(policy)
        }
        if arguments.count == 2, arguments[0] == "reset", ["stale-days", "notice", "all"].contains(arguments[1]) {
            return .reset(arguments[1])
        }
        throw CommandParserError.invalidValue(arguments.joined(separator: " "))
    }

    private static func parseTeardown(_ arguments: [String]) throws -> CellarCommand {
        var purge = false
        var confirmed = false
        for argument in arguments {
            switch argument {
            case "--purge": purge = true
            case "--yes": confirmed = true
            default: throw CommandParserError.unknownOption(argument)
            }
        }
        if purge && !confirmed { throw CommandParserError.unsafePurge }
        return .teardown(purge: purge, confirmed: confirmed)
    }

    private static func oneValue(_ name: String, _ arguments: [String]) throws -> String {
        guard arguments.count == 1, let value = arguments.first, !value.isEmpty else {
            throw CommandParserError.missingValue(name)
        }
        return value
    }

    private static func noArguments(_ command: CellarCommand, _ arguments: [String]) throws -> CellarCommand {
        guard arguments.isEmpty else { throw CommandParserError.unknownOption(arguments[0]) }
        return command
    }
}
