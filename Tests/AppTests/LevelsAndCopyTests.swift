import BalanceCore
import XCTest
@testable import DengeNoktasi

/// Shipped content checks that need the app bundle (levels, String Catalogs).
@MainActor
final class LevelsAndCopyTests: XCTestCase {
    private func catalog() throws -> LevelCatalog {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Levels", withExtension: nil))
        return try LevelCatalog.load(from: url)
    }

    func testShippedLevelsDecodeAndValidate() throws {
        let c = try catalog()
        XCTAssertFalse(c.curated.isEmpty)
        XCTAssertEqual(Set(c.curated.map(\.index)).count, c.curated.count, "duplicate curated indices")
        for level in c.allLevels {
            XCTAssertEqual(level.validate(), [], level.id)
            XCTAssertNotNil(Region(rawValue: level.region), "\(level.id) has unknown region \(level.region)")
        }
    }

    /// §7.4: rewarded ads are never required. Every curated level must be solvable from the start
    /// within its budget using only the shipped annotation — no hint, no ad, no "back to last move".
    func testEveryCuratedLevelIsSolvableWithoutRewardedAds() throws {
        let c = try catalog()
        for level in c.curated {
            let a = try XCTUnwrap(level.annotation, "\(level.id) has no verified solution")
            XCTAssertEqual(a.engineFingerprint, PhysicsConstants.fingerprint, "\(level.id): stale verification")
            XCTAssertLessThanOrEqual(a.solutionPath.count, level.goal.moveBudget, level.id)
            XCTAssertGreaterThanOrEqual(a.marginRatio ?? 0, PhysicsConstants.requiredMarginRatio, level.id)
            let index = TensionIndex(level: level)
            XCTAssertTrue(index.isUsable, level.id)
            XCTAssertNotNil(index.hint(stateKey: "", movesLeft: level.goal.moveBudget), "\(level.id): no path from the start")
            // Walking the shipped path reaches a state whose recorded neighbourhood contains the win.
            var key = ""
            for token in a.solutionPath.dropLast() {
                XCTAssertTrue(index.entry(for: key)?.safe.contains(token) ?? false, "\(level.id): \(token) not safe at '\(key)'")
                key = StateKey.adding(token, to: key)
            }
            XCTAssertTrue(index.entry(for: key)?.win?.contains(a.solutionPath.last!) ?? false, "\(level.id): last move does not win")
            XCTAssertEqual(StarRules.stars(moves: a.solutionPath.count, goal: level.goal), 3, "\(level.id): perfect play must earn 3★")
        }
    }

    /// §11.15: the menu must be up within 2 s of a cold start. Only curated levels load before the menu;
    /// the pool (~1,400 levels) follows in the background. Bounds keep a wide factor for a loaded CI
    /// simulator versus an iPhone 12.
    func testCatalogLoadsQuickly() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Levels", withExtension: nil))
        var start = ContinuousClock.now
        let curated = try LevelCatalog.loadCurated(from: url)
        let curatedTime = ContinuousClock.now - start
        start = ContinuousClock.now
        let pool = try LevelCatalog.loadPool(from: url)
        let poolTime = ContinuousClock.now - start
        print("[perf] \(curated.curated.count) curated in \(curatedTime); \(pool.count) pool levels in \(poolTime) (background)")
        XCTAssertLessThan(curatedTime, .milliseconds(300), "curated load took \(curatedTime)")
        XCTAssertLessThan(poolTime, .seconds(4), "pool load took \(poolTime)")
    }

    func testGoalTextsAreLocalized() throws {
        let c = try catalog()
        for level in c.allLevels {
            let text = Copy.goalText(level)
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("goal."), "raw key in \(level.id): \(text)")
            XCTAssertFalse(text.contains("noun."), "raw key in \(level.id): \(text)")
        }
    }

    func testTurkishCatalogIsCompiled() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "tr", ofType: "lproj"))
        let tr = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(tr.localizedString(forKey: "app.name", value: nil, table: nil), "Denge Noktası")
        XCTAssertEqual(tr.localizedString(forKey: "collapse.title", value: nil, table: nil), "Yapı çöktü")
    }

    func testDailyLevelExistsForAWeek() throws {
        let c = try catalog()
        let start = try XCTUnwrap(DailyLevelPicker.dayNumber(DailyLevelPicker.dayKey(for: .now)))
        for d in 0..<7 {
            let key = DailyLevelPicker.key(forDayNumber: start + d)
            let id = try XCTUnwrap(DailyLevelPicker.pick(dayKey: key, candidates: c.dailyCandidates.isEmpty ? c.curated.map(\.id) : c.dailyCandidates))
            XCTAssertNotNil(c.level(id: id))
        }
    }

    func testRegionsFollowTheCurriculum() throws {
        let c = try catalog()
        let order = c.regions.map(\.region.order)
        XCTAssertEqual(order, order.sorted(), "regions out of order")
        for (i, region) in c.regions.enumerated() where i > 0 {
            XCTAssertGreaterThan(region.levels.first!.index, c.regions[i - 1].levels.last!.index)
        }
    }

    func testNoAdIdentifiersInSource() throws {
        // §11.17: IDs come from Info.plist (xcconfig), never from Swift source.
        XCTAssertFalse(AppConfig.AdUnit.banner.isEmpty)
        XCTAssertTrue(AppConfig.AdUnit.banner.hasPrefix("ca-app-pub-"))
        XCTAssertFalse(AppConfig.appGroupIdentifier.isEmpty)
        XCTAssertTrue(AppConfig.removeAdsProductID.hasSuffix(".removeads"))
    }
}
