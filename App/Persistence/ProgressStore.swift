import BalanceCore
import Foundation
import Observation
import OSLog
import SwiftData

/// Plain copy of a level's progress for views (no SwiftData objects in view code).
struct LevelRecord: Equatable, Sendable {
    var stars: Int
    var bestMoves: Int?
    var completed: Bool
}

struct CompletionOutcome: Equatable {
    var stars: Int
    var previousStars: Int
    var bestMoves: Int
    var newBest: Bool
    var totalStars: Int
}

/// SwiftData container in the App Group so the widget's snapshot and the store live side by side.
/// Settings live here too (§3.2); ad pacing counters live in UserDefaults (`AdCapStore`).
@MainActor
@Observable
final class ProgressStore {
    private let log = Logger(subsystem: "Keystone", category: "progress")
    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var player: PlayerState

    private(set) var records: [String: LevelRecord] = [:]
    private(set) var totalStars = 0
    private(set) var settings = Settings()
    private(set) var streak = (count: 0, lastKey: String?.none)
    private(set) var dailyKeys: [String] = []
    private(set) var lastPlayedLevelId: String?
    private(set) var onboardingCompleted = false

    struct Settings: Equatable {
        var sound = true
        var music = false
        var haptics = true
        var leftHanded = false
    }

    init(inMemory: Bool = false) {
        let schema = Schema([PlayerState.self, LevelProgress.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier) {
            config = ModelConfiguration("Keystone", schema: schema, url: group.appendingPathComponent("Keystone.store"), cloudKitDatabase: .none)
        } else {
            // Unsigned simulator builds have no App Group; keep working with the app's own container.
            config = ModelConfiguration("Keystone", schema: schema, cloudKitDatabase: .none)
        }
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            Logger(subsystem: "Keystone", category: "progress").error("store failed, falling back to memory: \(error.localizedDescription)")
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try? context.fetch(FetchDescriptor<PlayerState>()).first {
            player = existing
        } else {
            let p = PlayerState()
            context.insert(p)
            player = p
            try? context.save()
        }
        reload()
    }

    private func reload() {
        let all = (try? context.fetch(FetchDescriptor<LevelProgress>())) ?? []
        var map: [String: LevelRecord] = [:]
        for p in all { map[p.levelId] = LevelRecord(stars: p.stars, bestMoves: p.bestMoves, completed: p.completedAt != nil) }
        records = map
        totalStars = player.totalStars
        settings = Settings(sound: player.soundEnabled, music: player.musicEnabled, haptics: player.hapticsEnabled, leftHanded: player.leftHandedHUD)
        streak = (player.dailyStreak, player.lastDailyCompletedKey)
        dailyKeys = player.dailyCompletedKeys
        lastPlayedLevelId = player.lastPlayedLevelId
        onboardingCompleted = player.onboardingCompleted
    }

    private func save() {
        do { try context.save() } catch { log.error("save failed: \(error.localizedDescription)") }
    }

    private func progress(for id: String) -> LevelProgress {
        var d = FetchDescriptor<LevelProgress>(predicate: #Predicate { $0.levelId == id })
        d.fetchLimit = 1
        if let p = try? context.fetch(d).first { return p }
        let p = LevelProgress(levelId: id)
        context.insert(p)
        return p
    }

    // MARK: Queries

    func record(_ id: String) -> LevelRecord { records[id] ?? LevelRecord(stars: 0, bestMoves: nil, completed: false) }
    func stars(_ id: String) -> Int { records[id]?.stars ?? 0 }
    var completedIds: Set<String> { Set(records.filter(\.value.completed).map(\.key)) }
    var endlessCursor: Int { player.endlessCursor }
    var endlessSeed: UInt64 { UInt64(bitPattern: player.endlessSeed) }
    var totalClears: Int { player.totalClears }
    var clearsWithoutHint: Int { player.clearsWithoutHint }

    // MARK: Updates

    func recordAttempt(_ id: String) {
        progress(for: id).attempts += 1
        player.lastPlayedLevelId = id
        lastPlayedLevelId = id
        save()
    }

    /// Keeps the best stars and fewest moves; recomputes the star total.
    @discardableResult
    func recordCompletion(_ id: String, moves: Int, stars: Int, usedHint: Bool, countsTowardStars: Bool) -> CompletionOutcome {
        let p = progress(for: id)
        let previous = p.stars
        let newBest = p.bestMoves.map { moves < $0 } ?? true
        if countsTowardStars { p.stars = max(p.stars, stars) }
        p.bestMoves = min(p.bestMoves ?? .max, moves)
        p.completedAt = p.completedAt ?? .now
        p.usedHint = p.usedHint || usedHint
        player.totalClears += 1
        if !usedHint { player.clearsWithoutHint += 1 }
        save()
        let all = (try? context.fetch(FetchDescriptor<LevelProgress>())) ?? []
        player.totalStars = all.reduce(0) { $0 + $1.stars }
        save()
        reload()
        return CompletionOutcome(stars: stars, previousStars: previous, bestMoves: p.bestMoves ?? moves, newBest: newBest, totalStars: totalStars)
    }

    func recordDailyCompletion(dayKey: String, at date: Date = .now) {
        player.dailyStreak = StreakRules.streakAfterCompleting(dayKey: dayKey, lastCompletedKey: player.lastDailyCompletedKey, streak: player.dailyStreak)
        if let last = player.lastDailyCompletedKey, (DailyLevelPicker.dayNumber(dayKey) ?? 0) < (DailyLevelPicker.dayNumber(last) ?? 0) {
            // Older day: keep the newer key.
        } else {
            player.lastDailyCompletedKey = dayKey
            player.lastDailyCompleted = date
        }
        if !player.dailyCompletedKeys.contains(dayKey) {
            player.dailyCompletedKeys = Array((player.dailyCompletedKeys + [dayKey]).suffix(60))
        }
        save()
        reload()
    }

    func advanceEndless() {
        player.endlessCursor += 1
        save()
    }

    func completeOnboarding() {
        player.onboardingCompleted = true
        onboardingCompleted = true
        save()
    }

    func update(_ change: (inout Settings) -> Void) {
        var s = settings
        change(&s)
        player.soundEnabled = s.sound
        player.musicEnabled = s.music
        player.hapticsEnabled = s.haptics
        player.leftHandedHUD = s.leftHanded
        save()
        settings = s
    }

    /// "Reset Progress…": stars, levels, streak and endless position. Settings and purchases stay.
    func resetProgress() {
        for p in (try? context.fetch(FetchDescriptor<LevelProgress>())) ?? [] { context.delete(p) }
        player.totalStars = 0
        player.dailyStreak = 0
        player.lastDailyCompleted = nil
        player.lastDailyCompletedKey = nil
        player.dailyCompletedKeys = []
        player.endlessCursor = 0
        player.lastPlayedLevelId = nil
        player.totalClears = 0
        player.clearsWithoutHint = 0
        save()
        reload()
    }
}
