import BalanceCore
import Foundation
import OSLog
import WidgetKit

/// Writes the widget's `ProgressSnapshot` into the App Group (today plus the next six days,
/// so the widget can roll over at midnight without the app running).
@MainActor
enum SharedSnapshotWriter {
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier)
    }

    static func write(store: ProgressStore, catalog: LevelCatalog, now: Date = .now, calendar: Calendar = .current) {
        guard let dir = directory else { return }
        let today = DailyLevelPicker.dayKey(for: now, calendar: calendar)
        guard let todayNumber = DailyLevelPicker.dayNumber(today) else { return }
        var days: [ProgressSnapshot.Day] = []
        for offset in 0..<7 {
            let key = DailyLevelPicker.key(forDayNumber: todayNumber + offset)
            guard let id = DailyLevelPicker.pick(dayKey: key, candidates: catalog.dailyCandidates),
                  let level = catalog.level(id: id) else { continue }
            days.append(.init(dayKey: key, levelId: id, par: level.goal.normalizedThresholds.first ?? level.goal.moveBudget,
                              silhouette: Silhouette(level: level)))
        }
        let snapshot = ProgressSnapshot(writtenAt: now, dailyStreak: store.streak.count, lastDailyCompletedKey: store.streak.lastKey,
                                        totalStars: store.totalStars, days: days)
        do {
            try snapshot.encoded().write(to: dir.appendingPathComponent(ProgressSnapshot.fileName), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Logger(subsystem: "Keystone", category: "widget").error("snapshot write failed: \(error.localizedDescription)")
        }
    }
}
