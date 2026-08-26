import XCTest
@testable import CellarCore

final class PackageSignalProviderTests: XCTestCase {
    func testFormulaRequiresAnExecutableInBinOrSbin() throws {
        let prefix = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let executable = prefix.appending(path: "Cellar/ripgrep/1.0/bin/rg")
        let library = prefix.appending(path: "Cellar/oniguruma/1.0/lib/libonig.dylib")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try Data().write(to: library)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: library.path)
        let provider = FilesystemPackageSignalProvider(prefix: prefix.path)

        XCTAssertTrue(provider.supportsUsageSignal(for: Self.formula(name: "ripgrep")))
        XCTAssertFalse(provider.supportsUsageSignal(for: Self.formula(name: "oniguruma")))
    }

    func testTapQualifiedFormulaUsesRackBasename() throws {
        let prefix = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let executable = prefix.appending(path: "Cellar/tool/1.0/sbin/tool")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        XCTAssertTrue(FilesystemPackageSignalProvider(prefix: prefix.path).supportsUsageSignal(for: Self.formula(name: "owner/tap/tool")))
    }

    private static func formula(name: String) -> InventoryPackage {
        InventoryPackage(
            id: "formula:\(name)",
            name: name,
            kind: .formula,
            installedOnRequest: true,
            isLeaf: true,
            isPinned: false,
            supportsUsageSignal: true,
            installedAt: nil,
            dependencies: [],
            appPaths: []
        )
    }
}
