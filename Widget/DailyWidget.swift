import SwiftUI
import WidgetKit

struct DailyEntry: TimelineEntry {
    let date: Date
}

struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyEntry { DailyEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) { completion(DailyEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        completion(Timeline(entries: [DailyEntry(date: .now)], policy: .atEnd))
    }
}

struct DailyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyWidget", provider: DailyProvider()) { _ in
            Text("Keystone").containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DailyWidgetBundle: WidgetBundle {
    var body: some Widget { DailyWidget() }
}
