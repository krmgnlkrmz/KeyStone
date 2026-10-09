import Foundation

/// Flat outline of a structure for the widget, map cells and menu background (no SpriteKit).
public struct Silhouette: Codable, Sendable, Hashable {
    public struct Shape: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable { case normal, fixed, keystone, rope }
        public var kind: Kind
        /// World outline at the design pose (y up).
        public var points: [Vec2]
    }

    public var shapes: [Shape]
    public var bounds: Rect2
    public var floorY: Double

    public init(shapes: [Shape], bounds: Rect2, floorY: Double) {
        self.shapes = shapes; self.bounds = bounds; self.floorY = floorY
    }

    public init(level: Level, removed: Set<String> = []) {
        var shapes: [Shape] = []
        for p in level.pieces where !removed.contains(p.id) {
            let kind: Shape.Kind = p.material == .brass ? .keystone : p.fixed ? .fixed : p.material == .rope ? .rope : .normal
            shapes.append(Shape(kind: kind, points: p.worldOutline.map { Vec2(($0.x * 10).rounded() / 10, ($0.y * 10).rounded() / 10) }))
        }
        for j in level.joints where j.type == .rope && !removed.contains(j.id ?? "") {
            guard let a = level.piece(j.a), let b = level.piece(j.b) else { continue }
            let pa = a.position + (j.anchorA ?? .zero).rotated(by: a.rotation)
            let pb = b.position + (j.anchorB ?? .zero).rotated(by: b.rotation)
            let d = pb - pa
            let len = max(d.length, 0.001)
            let n = Vec2(-d.y / len * 1.2, d.x / len * 1.2)
            shapes.append(Shape(kind: .rope, points: [pa + n, pb + n, pb - n, pa - n]))
        }
        self.shapes = shapes
        self.bounds = level.bounds
        self.floorY = level.resolvedFloorY
    }
}

/// Small state file the app writes into the App Group for the widget.
/// The widget never opens the SwiftData store (no migrations, no locking).
public struct ProgressSnapshot: Codable, Sendable, Equatable {
    public static let fileName = "progress-snapshot.json"
    public static let currentVersion = 1

    public struct Day: Codable, Sendable, Equatable {
        public var dayKey: String
        public var levelId: String
        public var par: Int
        public var silhouette: Silhouette
        public init(dayKey: String, levelId: String, par: Int, silhouette: Silhouette) {
            self.dayKey = dayKey; self.levelId = levelId; self.par = par; self.silhouette = silhouette
        }
    }

    public var version: Int
    public var writtenAt: Date
    public var dailyStreak: Int
    public var lastDailyCompletedKey: String?
    public var totalStars: Int
    /// Today and the following days, so the widget can roll over at midnight without the app.
    public var days: [Day]

    public init(version: Int = ProgressSnapshot.currentVersion, writtenAt: Date, dailyStreak: Int,
                lastDailyCompletedKey: String?, totalStars: Int, days: [Day]) {
        self.version = version; self.writtenAt = writtenAt; self.dailyStreak = dailyStreak
        self.lastDailyCompletedKey = lastDailyCompletedKey; self.totalStars = totalStars; self.days = days
    }

    public func day(for key: String) -> Day? { days.first { $0.dayKey == key } }

    public func isSolved(dayKey: String) -> Bool { StreakRules.isSolved(todayKey: dayKey, lastCompletedKey: lastDailyCompletedKey) }

    public func streak(on dayKey: String) -> Int {
        StreakRules.displayStreak(todayKey: dayKey, lastCompletedKey: lastDailyCompletedKey, streak: dailyStreak)
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> ProgressSnapshot {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(ProgressSnapshot.self, from: data)
    }
}
