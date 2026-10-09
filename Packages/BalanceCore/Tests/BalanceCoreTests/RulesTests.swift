import Foundation
import Testing
@testable import BalanceCore

@Suite("Stars")
struct StarRulesTests {
    @Test(arguments: [([5, 6, 7], 5, 3), ([5, 6, 7], 6, 2), ([5, 6, 7], 7, 1), ([5, 6, 7], 4, 3), ([7, 6, 5], 5, 3), ([7, 6, 5], 6, 2)])
    func starsForMoves(thresholds: [Int], moves: Int, expected: Int) {
        #expect(StarRules.stars(moves: moves, thresholds: thresholds) == expected)
    }

    @Test func finishingOverTheLastBoundStillEarnsOne() {
        #expect(StarRules.stars(moves: 9, thresholds: [5, 6, 7]) == 1)
    }

    @Test func nextStarBound() {
        #expect(StarRules.movesForNextStar(currentStars: 1, thresholds: [5, 6, 7]) == 6)
        #expect(StarRules.movesForNextStar(currentStars: 2, thresholds: [5, 6, 7]) == 5)
        #expect(StarRules.movesForNextStar(currentStars: 3, thresholds: [5, 6, 7]) == nil)
    }
}

@Suite("Ad frequency cap")
struct AdFrequencyCapTests {
    let cap = AdFrequencyCap()
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func afterClears(_ n: Int, from s: AdFrequencyCap.State = .init()) -> AdFrequencyCap.State {
        (0..<n).reduce(s) { st, _ in cap.recordingClear(st) }
    }

    @Test func nothingDuringTheGracePeriod() {
        for n in 0...3 { #expect(!cap.shouldShowInterstitial(state: afterClears(n), now: t0)) }
    }

    @Test func firstInterstitialOnTheThirdClearAfterGrace() {
        #expect(!cap.shouldShowInterstitial(state: afterClears(4), now: t0))
        #expect(!cap.shouldShowInterstitial(state: afterClears(5), now: t0))
        #expect(cap.shouldShowInterstitial(state: afterClears(6), now: t0))
    }

    @Test func ninetySecondsBetweenInterstitials() {
        var s = cap.recordingInterstitial(afterClears(6), at: t0)
        s = afterClears(3, from: s)
        #expect(!cap.shouldShowInterstitial(state: s, now: t0.addingTimeInterval(89)))
        #expect(cap.shouldShowInterstitial(state: s, now: t0.addingTimeInterval(90)))
    }

    @Test func intervalResetsAfterShowing() {
        let s = cap.recordingInterstitial(afterClears(6), at: t0)
        #expect(!cap.shouldShowInterstitial(state: afterClears(2, from: s), now: t0.addingTimeInterval(500)))
        #expect(cap.shouldShowInterstitial(state: afterClears(3, from: s), now: t0.addingTimeInterval(500)))
    }

    @Test func blockedClearCarriesOverToTheNextOne() {
        let s = cap.recordingInterstitial(afterClears(6), at: t0)
        let threeMore = afterClears(3, from: s)
        #expect(!cap.shouldShowInterstitial(state: threeMore, now: t0.addingTimeInterval(30)))
        #expect(cap.shouldShowInterstitial(state: afterClears(1, from: threeMore), now: t0.addingTimeInterval(120)))
    }

    @Test func rewardedAdBuysQuietTime() {
        let s = cap.recordingRewarded(afterClears(6), at: t0)
        #expect(!cap.shouldShowInterstitial(state: s, now: t0.addingTimeInterval(44)))
        #expect(cap.shouldShowInterstitial(state: s, now: t0.addingTimeInterval(45)))
    }

    @Test func removeAdsWins() {
        #expect(!cap.shouldShowInterstitial(state: afterClears(30), now: t0, adsRemoved: true))
    }
}

@Suite("Daily level and streak")
struct DailyTests {
    let ids = (1...40).map { "p-\($0)" }

    @Test func sameDaySameLevelAnyOrder() {
        let a = DailyLevelPicker.pick(dayKey: "2026-10-08", candidates: ids)
        let b = DailyLevelPicker.pick(dayKey: "2026-10-08", candidates: ids.reversed())
        #expect(a != nil && a == b)
    }

    @Test func consecutiveDaysDiffer() {
        let a = DailyLevelPicker.pick(dayKey: "2026-10-08", candidates: ids)
        let b = DailyLevelPicker.pick(dayKey: "2026-10-09", candidates: ids)
        #expect(a != b)
    }

    @Test func noRepeatWithinOnePass() {
        let start = DailyLevelPicker.dayNumber("2026-01-01")!
        let picks = (0..<ids.count).map { DailyLevelPicker.pick(dayKey: DailyLevelPicker.key(forDayNumber: start + $0), candidates: ids)! }
        #expect(Set(picks).count == ids.count)
    }

    @Test func dayKeyUsesTheLocalCalendarDay() {
        // 2026-10-08 22:30 UTC is already Oct 9 in Istanbul (UTC+3).
        let date = Date(timeIntervalSince1970: 1_791_498_600)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var ist = Calendar(identifier: .gregorian); ist.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        #expect(DailyLevelPicker.dayKey(for: date, calendar: utc) == "2026-10-08")
        #expect(DailyLevelPicker.dayKey(for: date, calendar: ist) == "2026-10-09")
    }

    @Test func civilDayRoundTrip() {
        for n in [-1, 0, 1, 20_000, 20_734, 30_000] {
            #expect(DailyLevelPicker.dayNumber(DailyLevelPicker.key(forDayNumber: n)) == n)
        }
        #expect(DailyLevelPicker.dayNumber("1970-01-01") == 0)
        #expect(DailyLevelPicker.dayNumber("2026-13-01") == nil)
    }

    @Test func streakRules() {
        #expect(StreakRules.streakAfterCompleting(dayKey: "2026-10-08", lastCompletedKey: "2026-10-07", streak: 6) == 7)
        #expect(StreakRules.streakAfterCompleting(dayKey: "2026-10-08", lastCompletedKey: "2026-10-08", streak: 7) == 7)
        #expect(StreakRules.streakAfterCompleting(dayKey: "2026-10-08", lastCompletedKey: "2026-10-05", streak: 9) == 1)
        #expect(StreakRules.streakAfterCompleting(dayKey: "2026-10-08", lastCompletedKey: nil, streak: 0) == 1)
        #expect(StreakRules.streakAfterCompleting(dayKey: "2026-03-01", lastCompletedKey: "2026-02-28", streak: 2) == 3)
        #expect(StreakRules.displayStreak(todayKey: "2026-10-08", lastCompletedKey: "2026-10-07", streak: 6) == 6)
        #expect(StreakRules.displayStreak(todayKey: "2026-10-09", lastCompletedKey: "2026-10-07", streak: 6) == 0)
    }

    @Test func weekStartsOnMonday() {
        let week = StreakRules.weekKeys(containing: "2026-10-08") // a Thursday
        #expect(week.first == "2026-10-05")
        #expect(week.last == "2026-10-11")
        #expect(week[3] == "2026-10-08")
    }
}

@Suite("Region unlock")
struct UnlockRulesTests {
    let regions = [(1...10).map { "a\($0)" }, (1...10).map { "b\($0)" }, (1...10).map { "c\($0)" }]

    @Test func seventyPercentOpensTheNextRegion() {
        #expect(UnlockRules.unlockedRegionCount(regions: regions, completed: []) == 1)
        let six = Set((1...6).map { "a\($0)" })
        #expect(UnlockRules.unlockedRegionCount(regions: regions, completed: six) == 1)
        #expect(UnlockRules.completionsMissing(toUnlock: 1, regions: regions, completed: six) == 1)
        let seven = six.union(["a10"])
        #expect(UnlockRules.unlockedRegionCount(regions: regions, completed: seven) == 2)
    }

    @Test func gatesAreSequential() {
        // Region C's prerequisite done, but region B still locked behind A.
        let onlyB = Set((1...10).map { "b\($0)" })
        #expect(UnlockRules.unlockedRegionCount(regions: regions, completed: onlyB) == 1)
        #expect(!UnlockRules.isRegionUnlocked(2, regions: regions, completed: onlyB))
    }

    @Test func oddSizesRoundUp() {
        #expect(UnlockRules.requiredCompletions(regionSize: 20) == 14)
        #expect(UnlockRules.requiredCompletions(regionSize: 3) == 3)
        #expect(UnlockRules.requiredCompletions(regionSize: 9) == 7)
    }
}
