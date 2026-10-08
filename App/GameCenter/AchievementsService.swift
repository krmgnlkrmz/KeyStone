import BalanceCore
import GameKit
import OSLog

/// Game Center achievements only (no leaderboards). Silent sign-in; nothing breaks without it.
@MainActor
final class AchievementsService {
    enum Achievement: String, CaseIterable {
        case firstRegion = "first_region"
        case stars50 = "stars_50"
        case stars100 = "stars_100"
        case noHint20 = "no_hint_20"
        case streak7 = "streak_7"
        case keystoneRegion = "keystone_region"
        case threeStars10 = "three_stars_10"
        case firstCollapse = "first_collapse"
        case allCurated = "all_curated"
        case endless25 = "endless_25"
    }

    private let log = Logger(subsystem: "Keystone", category: "gamecenter")
    private(set) var isAuthenticated = false
    private var reported: Set<String> = []

    func authenticate() {
        guard !AppConfig.isRunningTests else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            // Silent: never present the sign-in sheet on our own.
            if let error { self?.log.info("Game Center unavailable: \(error.localizedDescription)") }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated && viewController == nil
        }
    }

    func report(_ achievement: Achievement, percent: Double = 100) {
        guard isAuthenticated else { return }
        let id = AppConfig.achievementID(achievement.rawValue)
        guard percent < 100 || !reported.contains(id) else { return }
        let a = GKAchievement(identifier: id)
        a.percentComplete = min(100, percent)
        a.showsCompletionBanner = percent >= 100
        if percent >= 100 { reported.insert(id) }
        GKAchievement.report([a]) { [log] error in
            if let error { log.error("report failed: \(error.localizedDescription)") }
        }
    }

    /// Re-derives progress after a clear.
    func evaluate(progress: ProgressStore, catalog: LevelCatalog, endlessCleared: Int) {
        let completed = progress.completedIds
        let regions = catalog.regions
        if let first = regions.first, first.levels.allSatisfy({ completed.contains($0.id) }) { report(.firstRegion) }
        if let key = regions.first(where: { $0.region == .keystone }), key.levels.allSatisfy({ completed.contains($0.id) }) {
            report(.keystoneRegion)
        }
        report(.stars50, percent: Double(progress.totalStars) / 50 * 100)
        report(.stars100, percent: Double(progress.totalStars) / 100 * 100)
        report(.noHint20, percent: Double(progress.clearsWithoutHint) / 20 * 100)
        let threeStars = catalog.curated.filter { progress.stars($0.id) == 3 }.count
        report(.threeStars10, percent: Double(threeStars) / 10 * 100)
        if !catalog.curated.isEmpty, catalog.curated.allSatisfy({ completed.contains($0.id) }) { report(.allCurated) }
        if endlessCleared > 0 { report(.endless25, percent: Double(endlessCleared) / 25 * 100) }
        if progress.streak.count >= 7 { report(.streak7) } else { report(.streak7, percent: Double(progress.streak.count) / 7 * 100) }
    }

    func showDashboard() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .achievements) {}
    }
}
