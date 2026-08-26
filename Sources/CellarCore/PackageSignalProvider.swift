import Foundation

public protocol PackageSignalProviding {
    func supportsUsageSignal(for package: InventoryPackage) -> Bool
}

public struct FilesystemPackageSignalProvider: PackageSignalProviding, Sendable {
    private let prefix: URL

    public init(prefix: String) {
        self.prefix = URL(fileURLWithPath: prefix).standardizedFileURL
    }

    public func supportsUsageSignal(for package: InventoryPackage) -> Bool {
        guard package.kind == .formula else { return package.supportsUsageSignal }
        guard let rackName = package.name.split(separator: "/").last.map(String.init),
              PackageToken.isValid(rackName) else { return false }
        let rack = prefix.appending(path: "Cellar").appending(path: rackName)
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: rack,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for version in versions {
            for executableDirectory in ["bin", "sbin"] {
                let directory = version.appending(path: executableDirectory)
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let candidate as URL in enumerator where FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return true
                }
            }
        }
        return false
    }
}
