import Foundation

/// Map regions in play order. Level JSON names a region by `rawValue`.
public enum Region: String, Codable, Sendable, CaseIterable {
    case woodScaffold = "wood_scaffold"
    case stoneArch = "stone_arch"
    case ironTruss = "iron_truss"
    case ropeBridge = "rope_bridge"
    case steelCrane = "steel_crane"
    case counterweight = "counterweight"
    case keystone = "keystone"

    public var order: Int { Region.allCases.firstIndex(of: self)! }
}

/// Region gates: the first region is open; each next one opens once 70 % of the previous region is done.
public enum UnlockRules {
    public static let regionUnlockFraction = 0.7

    public static func requiredCompletions(regionSize: Int) -> Int {
        Int((Double(regionSize) * regionUnlockFraction).rounded(.up))
    }

    /// `regions` are the level ids of each region in play order.
    public static func unlockedRegionCount(regions: [[String]], completed: Set<String>) -> Int {
        guard !regions.isEmpty else { return 0 }
        var open = 1
        for i in 0..<(regions.count - 1) {
            let done = regions[i].filter(completed.contains).count
            if done >= requiredCompletions(regionSize: regions[i].count) { open = i + 2 } else { break }
        }
        return open
    }

    public static func isRegionUnlocked(_ index: Int, regions: [[String]], completed: Set<String>) -> Bool {
        index < unlockedRegionCount(regions: regions, completed: completed)
    }

    /// Completions still missing before region `index` opens (0 when open).
    public static func completionsMissing(toUnlock index: Int, regions: [[String]], completed: Set<String>) -> Int {
        guard index > 0, index < regions.count else { return 0 }
        if isRegionUnlocked(index, regions: regions, completed: completed) { return 0 }
        let prev = regions[index - 1]
        return max(0, requiredCompletions(regionSize: prev.count) - prev.filter(completed.contains).count)
    }
}
