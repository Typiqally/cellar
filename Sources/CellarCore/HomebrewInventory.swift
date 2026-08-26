import Foundation

public enum HomebrewInventoryError: LocalizedError {
    case invalidRoot

    public var errorDescription: String? { "Homebrew returned an invalid inventory document" }
}

public enum HomebrewInventoryDecoder {
    public static func decode(_ data: Data) throws -> HomebrewInventory {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HomebrewInventoryError.invalidRoot
        }
        var packages: [InventoryPackage] = []

        for formula in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = formula["name"] as? String else { continue }
            let fullName = formula["full_name"] as? String ?? name
            let installations = formula["installed"] as? [[String: Any]] ?? []
            let latest = installations.max { number($0["time"]) < number($1["time"]) }
            let runtimeDependencies = latest?["runtime_dependencies"] as? [[String: Any]] ?? []
            let dependencies = runtimeDependencies.compactMap { dependency -> String? in
                guard let dependencyName = dependency["full_name"] as? String else { return nil }
                return "formula:\(dependencyName)"
            }
            packages.append(InventoryPackage(
                id: "formula:\(fullName)",
                name: fullName,
                kind: .formula,
                installedOnRequest: latest?["installed_on_request"] as? Bool ?? false,
                isLeaf: true,
                isPinned: formula["pinned"] as? Bool ?? false,
                supportsUsageSignal: true,
                installedAt: date(latest?["time"]),
                dependencies: dependencies,
                appPaths: []
            ))
        }

        for cask in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String else { continue }
            let fullToken = cask["full_token"] as? String ?? token
            let artifacts = cask["artifacts"] as? [[String: Any]] ?? []
            let appPaths = artifacts.flatMap { artifact -> [String] in
                guard let apps = artifact["app"] as? [String] else { return [] }
                if let target = artifact["target"] as? String { return [target] }
                if let targets = artifact["target"] as? [String] { return targets }
                return apps.map { "/Applications/\($0)" }
            }
            let hasBinary = artifacts.contains { $0["binary"] != nil }
            let dependencies = decodeCaskDependencies(cask["depends_on"])
            packages.append(InventoryPackage(
                id: "cask:\(fullToken)",
                name: fullToken,
                kind: .cask,
                installedOnRequest: true,
                isLeaf: true,
                isPinned: cask["pinned"] as? Bool ?? false,
                supportsUsageSignal: !appPaths.isEmpty || hasBinary,
                installedAt: date(cask["installed_time"]),
                dependencies: dependencies,
                appPaths: appPaths
            ))
        }

        let dependedUpon = Set(packages.flatMap(\.dependencies))
        packages = packages.map { package in
            var updated = package
            updated.isLeaf = !dependedUpon.contains(package.id)
            return updated
        }
        return HomebrewInventory(packages: packages)
    }

    private static func decodeCaskDependencies(_ value: Any?) -> [String] {
        guard let dictionary = value as? [String: Any] else { return [] }
        var result: [String] = []
        if let formulae = dictionary["formula"] as? [String] {
            result.append(contentsOf: formulae.map { "formula:\($0)" })
        } else if let formula = dictionary["formula"] as? String {
            result.append("formula:\(formula)")
        }
        if let casks = dictionary["cask"] as? [String] {
            result.append(contentsOf: casks.map { "cask:\($0)" })
        } else if let cask = dictionary["cask"] as? String {
            result.append("cask:\(cask)")
        }
        return result
    }

    private static func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }

    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }
}
