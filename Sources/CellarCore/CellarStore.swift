import CSQLite
import Darwin
import Foundation

public enum CellarStoreError: LocalizedError {
    case sqlite(String)
    case invalidStoredValue(String)

    public var errorDescription: String? {
        switch self {
        case let .sqlite(message): message
        case let .invalidStoredValue(name): "invalid value stored for \(name)"
        }
    }
}

public final class CellarStore {
    public let directory: URL
    public let databaseURL: URL
    public let configurationURL: URL

    private var database: OpaquePointer?

    public init(directory: URL) throws {
        self.directory = directory
        databaseURL = directory.appending(path: "state.sqlite3")
        configurationURL = directory.appending(path: "config.json")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard chmod(directory.path, S_IRWXU) == 0 else {
            throw CellarStoreError.sqlite("could not secure state directory")
        }

        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK else {
            throw CellarStoreError.sqlite(Self.message(from: database))
        }
        guard chmod(databaseURL.path, S_IRUSR | S_IWUSR) == 0 else {
            throw CellarStoreError.sqlite("could not secure state database")
        }
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    public func loadConfiguration() throws -> CellarConfiguration {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return .default }
        return try ConfigurationCodec.decode(Data(contentsOf: configurationURL))
    }

    public func saveConfiguration(_ configuration: CellarConfiguration) throws {
        let data = try ConfigurationCodec.encode(configuration)
        try data.write(to: configurationURL, options: .atomic)
        guard chmod(configurationURL.path, S_IRUSR | S_IWUSR) == 0 else {
            throw CellarStoreError.sqlite("could not secure configuration file")
        }
    }

    public func replaceInventory(_ packages: [TrackedPackage]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let sql = """
            INSERT INTO packages (
                id, name, kind, installed_on_request, is_leaf, is_pinned,
                is_running_service, is_ignored, supports_usage_signal,
                observed_since, last_used_at, evidence_source, present
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                kind = excluded.kind,
                installed_on_request = excluded.installed_on_request,
                is_leaf = excluded.is_leaf,
                is_pinned = excluded.is_pinned,
                is_running_service = excluded.is_running_service,
                supports_usage_signal = excluded.supports_usage_signal,
                observed_since = MIN(packages.observed_since, excluded.observed_since),
                present = 1
            """
            try execute("UPDATE packages SET present = 0")
            for package in packages {
                try withStatement(sql) { statement in
                    try bind(package.id, to: 1, in: statement)
                    try bind(package.name, to: 2, in: statement)
                    try bind(package.kind.rawValue, to: 3, in: statement)
                    try bind(package.installedOnRequest, to: 4, in: statement)
                    try bind(package.isLeaf, to: 5, in: statement)
                    try bind(package.isPinned, to: 6, in: statement)
                    try bind(package.isRunningService, to: 7, in: statement)
                    try bind(package.isIgnored, to: 8, in: statement)
                    try bind(package.supportsUsageSignal, to: 9, in: statement)
                    try bind(package.observedSince.timeIntervalSince1970, to: 10, in: statement)
                    try bind(package.lastUsedAt?.timeIntervalSince1970, to: 11, in: statement)
                    try bind(package.evidenceSource?.rawValue, to: 12, in: statement)
                    try stepDone(statement)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func recordUsage(_ ownership: PackageOwnership, at date: Date, source: EvidenceSource) throws {
        let sql = """
        UPDATE packages
        SET last_used_at = CASE
                WHEN last_used_at IS NULL OR last_used_at < ? THEN ?
                ELSE last_used_at
            END,
            evidence_source = CASE
                WHEN last_used_at IS NULL OR last_used_at < ? THEN ?
                ELSE evidence_source
            END
        WHERE id = ? OR id LIKE ? ESCAPE '\\'
        """
        let timestamp = date.timeIntervalSince1970
        let escapedToken = ownership.token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        try withStatement(sql) { statement in
            try bind(timestamp, to: 1, in: statement)
            try bind(timestamp, to: 2, in: statement)
            try bind(timestamp, to: 3, in: statement)
            try bind(source.rawValue, to: 4, in: statement)
            try bind(ownership.id, to: 5, in: statement)
            try bind("\(ownership.kind.rawValue):%/\(escapedToken)", to: 6, in: statement)
            try stepDone(statement)
        }
    }

    public func packages(includeAbsent: Bool = false) throws -> [TrackedPackage] {
        let sql = """
        SELECT id, name, kind, installed_on_request, is_leaf, is_pinned,
               is_running_service, is_ignored, supports_usage_signal,
               observed_since, last_used_at, evidence_source
        FROM packages
        \(includeAbsent ? "" : "WHERE present = 1")
        ORDER BY name COLLATE NOCASE
        """
        return try withStatement(sql) { statement in
            var result: [TrackedPackage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let kind = PackageKind(rawValue: text(at: 2, in: statement)),
                      let observed = double(at: 9, in: statement) else {
                    throw CellarStoreError.invalidStoredValue("package")
                }
                let evidence = optionalText(at: 11, in: statement).flatMap(EvidenceSource.init(rawValue:))
                result.append(TrackedPackage(
                    id: text(at: 0, in: statement),
                    name: text(at: 1, in: statement),
                    kind: kind,
                    installedOnRequest: sqlite3_column_int(statement, 3) != 0,
                    isLeaf: sqlite3_column_int(statement, 4) != 0,
                    isPinned: sqlite3_column_int(statement, 5) != 0,
                    isRunningService: sqlite3_column_int(statement, 6) != 0,
                    isIgnored: sqlite3_column_int(statement, 7) != 0,
                    supportsUsageSignal: sqlite3_column_int(statement, 8) != 0,
                    observedSince: Date(timeIntervalSince1970: observed),
                    lastUsedAt: double(at: 10, in: statement).map(Date.init(timeIntervalSince1970:)),
                    evidenceSource: evidence
                ))
            }
            return result
        }
    }

    public func setIgnored(packageID: String, ignored: Bool) throws {
        try withStatement("UPDATE packages SET is_ignored = ? WHERE id = ? OR name = ?") { statement in
            try bind(ignored, to: 1, in: statement)
            try bind(packageID, to: 2, in: statement)
            try bind(packageID, to: 3, in: statement)
            try stepDone(statement)
        }
    }

    public func metadata(_ key: String) throws -> String? {
        try withStatement("SELECT value FROM metadata WHERE key = ?") { statement in
            try bind(key, to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return text(at: 0, in: statement)
        }
    }

    public func setMetadata(_ value: String?, for key: String) throws {
        if let value {
            try withStatement("INSERT INTO metadata(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value") { statement in
                try bind(key, to: 1, in: statement)
                try bind(value, to: 2, in: statement)
                try stepDone(statement)
            }
        } else {
            try withStatement("DELETE FROM metadata WHERE key = ?") { statement in
                try bind(key, to: 1, in: statement)
                try stepDone(statement)
            }
        }
    }

    private func migrate() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA busy_timeout=2000")
        try execute("""
        CREATE TABLE IF NOT EXISTS packages (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('formula', 'cask')),
            installed_on_request INTEGER NOT NULL,
            is_leaf INTEGER NOT NULL,
            is_pinned INTEGER NOT NULL,
            is_running_service INTEGER NOT NULL,
            is_ignored INTEGER NOT NULL,
            supports_usage_signal INTEGER NOT NULL,
            observed_since REAL NOT NULL,
            last_used_at REAL,
            evidence_source TEXT,
            present INTEGER NOT NULL DEFAULT 1
        )
        """)
        try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? Self.message(from: database)
            sqlite3_free(errorMessage)
            throw CellarStoreError.sqlite(message)
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CellarStoreError.sqlite(Self.message(from: database))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
        let result: Int32
        if let value {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            result = sqlite3_bind_text(statement, index, value, -1, transient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw CellarStoreError.sqlite(Self.message(from: database)) }
    }

    private func bind(_ value: Double?, to index: Int32, in statement: OpaquePointer) throws {
        let result = value.map { sqlite3_bind_double(statement, index, $0) } ?? sqlite3_bind_null(statement, index)
        guard result == SQLITE_OK else { throw CellarStoreError.sqlite(Self.message(from: database)) }
    }

    private func bind(_ value: Bool, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int(statement, index, value ? 1 : 0) == SQLITE_OK else {
            throw CellarStoreError.sqlite(Self.message(from: database))
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CellarStoreError.sqlite(Self.message(from: database))
        }
    }

    private func text(at index: Int32, in statement: OpaquePointer) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func optionalText(at index: Int32, in statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return text(at: index, in: statement)
    }

    private func double(at index: Int32, in statement: OpaquePointer) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private static func message(from database: OpaquePointer?) -> String {
        database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "unknown SQLite error"
    }
}
