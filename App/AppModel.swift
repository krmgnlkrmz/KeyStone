import BalanceCore
import Foundation
import Observation
import OSLog
import SwiftUI

enum LaunchPhase: Equatable {
    case splash
    /// UMP form may be on screen ("Waiting for your privacy choices").
    case consent
    /// One-screen primer before the system tracking prompt.
    case trackingPrimer
    case ready
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Root state: services, catalog, launch sequence, and level bookkeeping shared by screens.
@MainActor
@Observable
final class AppModel {
    private let log = Logger(subsystem: "Keystone", category: "app")

    let progress: ProgressStore
    let ads: AdsCoordinator
    let store: StoreManager
    let haptics = Haptics()
    let sound = SoundPlayer()
    let achievements = AchievementsService()
    let router = AppRouter()

    private(set) var catalog: LevelCatalog = .empty
    /// The pool (Daily, Endless) loads right after the menu is up; until then those two wait.
    private(set) var poolReady = false
    /// Seconds from process start to the main menu's first appearance (§11: ≤ 2 s on a device).
    private(set) var launchToMenu: TimeInterval?
    /// The same clock at `AppModel.init` (everything before it is dyld, frameworks and the runtime) and
    /// when the curated catalog was decoded, so a slow launch shows where its time went.
    @ObservationIgnored private(set) var launchToInit: TimeInterval?
    @ObservationIgnored private(set) var launchToCatalog: TimeInterval?
    private(set) var launchPhase: LaunchPhase = .splash
    private(set) var toast: String?
    /// 0.3 s ink curtain before an interstitial; kept here so it survives the swap to the next level.
    var curtain = false
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var silhouetteCache: [String: Silhouette] = [:]
    @ObservationIgnored private var engineChecked = false
    /// Local day key, refreshed when the app becomes active (daily rollover).
    private(set) var todayKey: String = DailyLevelPicker.dayKey(for: .now)
    /// Endless levels cleared this install (achievement).
    private(set) var endlessCleared: Int = UserDefaults.standard.integer(forKey: "endless.cleared")

    var appearance: AppearancePreference {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    init(inMemoryStore: Bool = false) {
        launchToInit = AppConfig.processStart.map { Date().timeIntervalSince($0) }
        progress = ProgressStore(inMemory: inMemoryStore)
        ads = AdsCoordinator()
        store = StoreManager()
        appearance = AppearancePreference(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        ads.adsRemoved = store.adsRemoved
        store.onChange = { [weak self] owned in
            guard let self else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { self.ads.adsRemoved = owned }
            if owned { self.showToast(String(localized: "store.thanks")) }
        }
        applySettings()
    }

    func applySettings() {
        let s = progress.settings
        sound.effectsEnabled = s.sound
        sound.musicEnabled = s.music
        haptics.enabled = s.haptics
    }

    /// Called when the main menu first appears; later visits keep the cold-start figure.
    func noteMenuShown() {
        guard launchToMenu == nil, let start = AppConfig.processStart else { return }
        let seconds = Date().timeIntervalSince(start)
        launchToMenu = seconds
        log.info("menu \(seconds, format: .fixed(precision: 3), privacy: .public) s after process start (init \(self.launchToInit ?? -1, format: .fixed(precision: 3), privacy: .public) s, catalog \(self.launchToCatalog ?? -1, format: .fixed(precision: 3), privacy: .public) s)")
    }

    // MARK: Launch (§7.3)

    func bootstrap() async {
        let splashStart = ContinuousClock.now
        catalog = await Self.loadCatalog()
        launchToCatalog = AppConfig.processStart.map { Date().timeIntervalSince($0) }
        // Prices and a fresh entitlement check need the App Store, which can take seconds (or fail) on a
        // slow network. The menu shows with the cached entitlement; `store.onChange` updates it after.
        Task { await store.load() }
        Task { await loadPool() }
        achievements.authenticate()

        // Keep the splash up for at least 1.2 s so it reads as intentional.
        let elapsed = ContinuousClock.now - splashStart
        if elapsed < .milliseconds(1200) { try? await Task.sleep(for: .milliseconds(1200) - elapsed) }

        if AppConfig.isRunningTests {
            seedForUITests()
            launchPhase = .ready
            return
        }
        // A returning player who has nothing left to answer goes straight to the menu; the consent refresh
        // (network) and then MobileAds.start run behind it, in that order. A form UMP still requires is
        // presented over the menu.
        if progress.onboardingCompleted && !(TrackingAuthorization.needsPrompt && ads.storedConsentAllowsAds) {
            withAnimation(.easeOut(duration: 0.3)) { launchPhase = .ready }
            Task {
                await ads.gatherConsent()
                await ads.startIfAllowed()
            }
            return
        }
        launchPhase = .consent
        await ads.gatherConsent()
        if TrackingAuthorization.needsPrompt && ads.canRequestAds {
            withAnimation(.easeOut(duration: 0.35)) { launchPhase = .trackingPrimer }
            return // continues in `trackingPrimerContinue()`
        }
        await finishLaunch()
    }

    func trackingPrimerContinue() async {
        await TrackingAuthorization.request()
        await finishLaunch()
    }

    /// Consent (and the tracking question) are settled: the menu shows at once, and MobileAds.start
    /// (which can take seconds while adapters initialise) completes behind it.
    private func finishLaunch() async {
        progress.completeOnboarding()
        withAnimation(.easeOut(duration: 0.3)) { launchPhase = .ready }
        await ads.startIfAllowed()
    }

    private func seedForUITests() {
        let n = AppConfig.uiTestSeedLevels
        guard n > 0 else { return }
        for (i, level) in catalog.curated.prefix(n).enumerated() {
            progress.recordCompletion(level.id, moves: level.goal.moveBudget, stars: [3, 2, 3, 1, 3][i % 5],
                                      usedHint: false, countsTowardStars: true)
        }
        progress.recordDailyCompletion(dayKey: DailyLevelPicker.key(forDayNumber: (DailyLevelPicker.dayNumber(todayKey) ?? 1) - 1))
    }

    /// Curated levels only, before the menu: ~1 MB instead of ~15 MB on the cold-start path.
    nonisolated private static func loadCatalog() async -> LevelCatalog {
        guard let url = Bundle.main.url(forResource: "Levels", withExtension: nil) else { return .empty }
        do {
            return try LevelCatalog.loadCurated(from: url)
        } catch {
            Logger(subsystem: "Keystone", category: "app").error("level catalog failed: \(error.localizedDescription)")
            return .empty
        }
    }

    nonisolated private static func loadPoolLevels() async -> [Level] {
        guard let url = Bundle.main.url(forResource: "Levels", withExtension: nil) else { return [] }
        do {
            return try LevelCatalog.loadPool(from: url)
        } catch {
            Logger(subsystem: "Keystone", category: "app").error("level pool failed: \(error.localizedDescription)")
            return []
        }
    }

    private func loadPool() async {
        let pool = await Self.loadPoolLevels()
        catalog = catalog.adding(pool: pool)
        poolReady = true
        checkEngineFingerprint()
        SharedSnapshotWriter.write(store: progress, catalog: catalog)
    }

    /// Annotations made with other physics constants are ignored (tension and hints off, game playable).
    private func checkEngineFingerprint() {
        guard !engineChecked else { return }
        engineChecked = true
        let stale = catalog.allLevels.filter { ($0.annotation?.engineFingerprint).map { $0 != PhysicsConstants.fingerprint } ?? false }
        if !stale.isEmpty {
            log.notice("\(stale.count) levels have a stale engine fingerprint (runtime \(PhysicsConstants.fingerprint, privacy: .public)); hints and tension disabled for them")
        }
    }

    func sceneBecameActive() {
        let key = DailyLevelPicker.dayKey(for: .now)
        if key != todayKey {
            todayKey = key
            if poolReady { SharedSnapshotWriter.write(store: progress, catalog: catalog) }
        }
        ads.preload()
    }

    // MARK: Toasts

    func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }

    // MARK: Levels

    func silhouette(for level: Level) -> Silhouette {
        if let s = silhouetteCache[level.id] { return s }
        let s = Silhouette(level: level)
        silhouetteCache[level.id] = s
        return s
    }

    var regionLevelIds: [[String]] { catalog.regionLevelIds }

    func isRegionUnlocked(_ index: Int) -> Bool {
        UnlockRules.isRegionUnlocked(index, regions: regionLevelIds, completed: progress.completedIds)
    }

    func isLevelUnlocked(_ id: String) -> Bool {
        guard let r = catalog.regionIndex(of: id) else { return false }
        return isRegionUnlocked(r)
    }

    /// The level the Continue card offers: first unfinished level in an open region.
    var nextCampaignLevel: Level? {
        let done = progress.completedIds
        for (i, region) in catalog.regions.enumerated() where isRegionUnlocked(i) {
            if let l = region.levels.first(where: { !done.contains($0.id) }) { return l }
        }
        return catalog.curated.last
    }

    /// Nil until the pool is in: the pick depends on the whole candidate list.
    var dailyLevel: Level? {
        guard poolReady else { return nil }
        return DailyLevelPicker.pick(dayKey: todayKey, candidates: catalog.dailyCandidates).flatMap { catalog.level(id: $0) }
    }

    var dailySolvedToday: Bool { StreakRules.isSolved(todayKey: todayKey, lastCompletedKey: progress.streak.lastKey) }
    var displayStreak: Int { StreakRules.displayStreak(todayKey: todayKey, lastCompletedKey: progress.streak.lastKey, streak: progress.streak.count) }

    var endlessNumber: Int { progress.endlessCursor + 1 }

    func endlessLevel() -> Level? {
        guard poolReady else { return nil }
        return catalog.endlessLevel(seed: progress.endlessSeed, cursor: progress.endlessCursor)
    }

    // MARK: Navigation

    func play(_ level: Level) {
        guard isLevelUnlocked(level.id) else { return }
        router.game = GameLaunch(levelId: level.id, mode: .campaign)
    }

    func playDaily() {
        guard let level = dailyLevel else { return }
        router.sheet = nil
        router.game = GameLaunch(levelId: level.id, mode: .daily(dayKey: todayKey))
    }

    func playEndless() {
        guard let level = endlessLevel() else { return }
        router.game = GameLaunch(levelId: level.id, mode: .endless(number: endlessNumber))
    }

    func noteEndlessCleared() {
        endlessCleared += 1
        UserDefaults.standard.set(endlessCleared, forKey: "endless.cleared")
        progress.advanceEndless()
    }

    func handle(url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return }
        switch url.host() {
        case "daily":
            guard launchPhase == .ready, router.game == nil else { return }
            router.sheet = .daily
        default:
            break
        }
    }

    func resetProgress() {
        progress.resetProgress()
        ads.cap.reset()
        SharedSnapshotWriter.write(store: progress, catalog: catalog)
        showToast(String(localized: "settings.reset.done"))
    }
}
