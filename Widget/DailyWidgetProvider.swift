import BalanceCore
import Foundation
import WidgetKit

struct DailyEntry: TimelineEntry {
    let date: Date
    let dayKey: String
    let day: ProgressSnapshot.Day?
    let streak: Int
    let solved: Bool
}

/// Reads the snapshot the app writes into the App Group. One entry until midnight, then the next day.
struct DailyWidgetProvider: TimelineProvider {
    private var snapshotURL: URL? {
        let group = (Bundle.main.object(forInfoDictionaryKey: "DNAppGroupIdentifier") as? String) ?? ""
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent(ProgressSnapshot.fileName)
    }

    private func loadSnapshot() -> ProgressSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? ProgressSnapshot.decode(data)
    }

    func entry(at date: Date) -> DailyEntry {
        let key = DailyLevelPicker.dayKey(for: date)
        let snap = loadSnapshot()
        return DailyEntry(date: date, dayKey: key, day: snap?.day(for: key),
                          streak: snap?.streak(on: key) ?? 0, solved: snap?.isSolved(dayKey: key) ?? false)
    }

    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: .now, dayKey: DailyLevelPicker.dayKey(for: .now), day: nil, streak: 6, solved: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        // Today now, tomorrow at midnight; the app also reloads timelines whenever progress changes.
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight.addingTimeInterval(60))))
    }
}
