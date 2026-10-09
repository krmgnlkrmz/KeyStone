import BalanceCore
import XCTest
@testable import DengeNoktasi

@MainActor
final class PersistenceTests: XCTestCase {
    func testCompletionKeepsBestStarsAndFewestMoves() {
        let store = ProgressStore(inMemory: true)
        store.recordCompletion("c-010", moves: 6, stars: 2, usedHint: false, countsTowardStars: true)
        let worse = store.recordCompletion("c-010", moves: 7, stars: 1, usedHint: true, countsTowardStars: true)
        XCTAssertEqual(store.stars("c-010"), 2)
        XCTAssertEqual(store.record("c-010").bestMoves, 6)
        XCTAssertFalse(worse.newBest)
        let better = store.recordCompletion("c-010", moves: 5, stars: 3, usedHint: false, countsTowardStars: true)
        XCTAssertTrue(better.newBest)
        XCTAssertEqual(store.totalStars, 3)
        XCTAssertEqual(store.totalClears, 3)
        XCTAssertEqual(store.clearsWithoutHint, 2)
    }

    func testDailyAndEndlessDoNotAddMapStars() {
        let store = ProgressStore(inMemory: true)
        store.recordCompletion("p-1", moves: 3, stars: 3, usedHint: false, countsTowardStars: false)
        XCTAssertEqual(store.totalStars, 0)
        XCTAssertTrue(store.completedIds.contains("p-1"))
    }

    func testDailyStreak() {
        let store = ProgressStore(inMemory: true)
        store.recordDailyCompletion(dayKey: "2026-10-06")
        store.recordDailyCompletion(dayKey: "2026-10-07")
        store.recordDailyCompletion(dayKey: "2026-10-08")
        XCTAssertEqual(store.streak.count, 3)
        XCTAssertEqual(store.streak.lastKey, "2026-10-08")
        XCTAssertEqual(store.dailyKeys.suffix(3), ["2026-10-06", "2026-10-07", "2026-10-08"])
        store.recordDailyCompletion(dayKey: "2026-10-10")
        XCTAssertEqual(store.streak.count, 1)
    }

    func testResetKeepsSettings() {
        let store = ProgressStore(inMemory: true)
        store.update { $0.leftHanded = true; $0.sound = false }
        store.recordCompletion("c-001", moves: 1, stars: 3, usedHint: false, countsTowardStars: true)
        store.resetProgress()
        XCTAssertEqual(store.totalStars, 0)
        XCTAssertTrue(store.completedIds.isEmpty)
        XCTAssertTrue(store.settings.leftHanded)
        XCTAssertFalse(store.settings.sound)
    }

    func testAdCapPersistsAcrossInstances() throws {
        let suite = "adcap-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = AdCapStore(defaults: defaults)
        for _ in 0..<6 { a.recordClear() }
        let t0 = Date()
        XCTAssertTrue(AdCapStore(defaults: defaults).shouldShowInterstitial(now: t0, adsRemoved: false))
        XCTAssertFalse(AdCapStore(defaults: defaults).shouldShowInterstitial(now: t0, adsRemoved: true))
        a.recordInterstitial(at: t0)
        XCTAssertFalse(AdCapStore(defaults: defaults).shouldShowInterstitial(now: t0.addingTimeInterval(200), adsRemoved: false))
    }
}
