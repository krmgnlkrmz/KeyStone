import Foundation

/// All shipped levels, loaded from the bundle's `Levels/` folder (`curated/*.json`, `pool/*.json`).
/// A pool file may hold a single level or an array of levels.
public struct LevelCatalog: Sendable {
    public let curated: [Level]
    public let pool: [Level]
    private let byId: [String: Level]

    public init(curated: [Level], pool: [Level]) {
        self.curated = curated.sorted { $0.index < $1.index }
        self.pool = pool.sorted { $0.id < $1.id }
        var map: [String: Level] = [:]
        for l in curated + pool { map[l.id] = l }
        byId = map
    }

    public static let empty = LevelCatalog(curated: [], pool: [])

    public func level(id: String) -> Level? { byId[id] }

    public var allLevels: [Level] { curated + pool }

    /// Curated levels grouped by region, in play order. Regions without levels are skipped.
    public var regions: [(region: Region, levels: [Level])] {
        Region.allCases.compactMap { r in
            let ls = curated.filter { $0.region == r.rawValue }
            return ls.isEmpty ? nil : (r, ls)
        }
    }

    public var regionLevelIds: [[String]] { regions.map { $0.levels.map(\.id) } }

    public func regionIndex(of levelId: String) -> Int? {
        regions.firstIndex { $0.levels.contains { $0.id == levelId } }
    }

    /// Next curated level after `id`, or nil at the end.
    public func next(after id: String) -> Level? {
        guard let i = curated.firstIndex(where: { $0.id == id }), i + 1 < curated.count else { return nil }
        return curated[i + 1]
    }

    /// Daily candidates: the pool plus curated levels past the tutorial.
    public var dailyCandidates: [String] {
        curated.filter { $0.index > 10 }.map(\.id) + pool.map(\.id)
    }

    /// Per-player order through the pool, fixed by the player's seed.
    public func endlessOrder(seed: UInt64) -> [String] {
        var ids = pool.map(\.id)
        if ids.isEmpty { ids = curated.filter { $0.index > 10 }.map(\.id) }
        var rng = SplitMix64(seed: seed)
        // Explicit Fisher–Yates: the standard library's shuffle algorithm is not a stability promise.
        if ids.count > 1 {
            for i in stride(from: ids.count - 1, to: 0, by: -1) {
                let j = Int(rng.next() % UInt64(i + 1))
                ids.swapAt(i, j)
            }
        }
        return ids
    }

    public func endlessLevel(seed: UInt64, cursor: Int) -> Level? {
        let order = endlessOrder(seed: seed)
        guard !order.isEmpty else { return nil }
        return byId[order[((cursor % order.count) + order.count) % order.count]]
    }

    // MARK: Loading

    /// Curated levels and the pool.
    public static func load(from directory: URL) throws -> LevelCatalog {
        LevelCatalog(curated: try levels(in: directory, "curated"), pool: try levels(in: directory, "pool"))
    }

    /// Curated levels only: what the menu and the map need. The app loads the pool after the menu is up.
    public static func loadCurated(from directory: URL) throws -> LevelCatalog {
        LevelCatalog(curated: try levels(in: directory, "curated"), pool: [])
    }

    public static func loadPool(from directory: URL) throws -> [Level] {
        try levels(in: directory, "pool")
    }

    /// This catalog with pool levels added.
    public func adding(pool more: [Level]) -> LevelCatalog {
        LevelCatalog(curated: curated, pool: pool + more)
    }

    private static func levels(in directory: URL, _ sub: String) throws -> [Level] {
        let dir = directory.appendingPathComponent(sub, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let jsons = files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Files decode independently, so they are spread over the cores (the cold start reads 80 of them);
        // results keep file order.
        let results = DecodeResults(count: jsons.count)
        DispatchQueue.concurrentPerform(iterations: jsons.count) { i in
            results.set(i, Result { try decodeLevels(Data(contentsOf: jsons[i])) })
        }
        return try results.all.flatMap { try $0.get() }
    }

    /// Decodes a single level object or an array of levels. The first character decides which, so a
    /// file is parsed once (trying an array first parsed every single-level file twice).
    public static func decodeLevels(_ data: Data) throws -> [Level] {
        let decoder = JSONDecoder()
        let first = data.first { !$0.isJSONWhitespace }
        if first == UInt8(ascii: "[") { return try decoder.decode([Level].self, from: data) }
        return [try decoder.decode(Level.self, from: data)]
    }
}

/// Per-file decode results, written from `concurrentPerform`'s workers (each index exactly once).
private final class DecodeResults: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [Result<[Level], Error>]

    init(count: Int) { slots = Array(repeating: .success([]), count: count) }

    func set(_ index: Int, _ result: Result<[Level], Error>) {
        lock.lock()
        slots[index] = result
        lock.unlock()
    }

    var all: [Result<[Level], Error>] {
        lock.lock()
        defer { lock.unlock() }
        return slots
    }
}

private extension UInt8 {
    var isJSONWhitespace: Bool { self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09 }
}

/// Small deterministic PRNG for shuffles that must match on every device.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
