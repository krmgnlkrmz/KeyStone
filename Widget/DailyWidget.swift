import BalanceCore
import SwiftUI
import WidgetKit

struct DailyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyWidget", provider: DailyWidgetProvider()) { entry in
            DailyWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName(Text("widget.name"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DailyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyEntry

    private var url: URL? {
        let scheme = (Bundle.main.object(forInfoDictionaryKey: "DNURLScheme") as? String) ?? "dengenoktasi"
        return URL(string: "\(scheme)://daily")
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(url)
    }

    private var art: some View {
        ZStack {
            if let s = entry.day?.silhouette {
                SilhouetteShape(silhouette: s, excludeKeystone: true).fill(Color("LabelSecondary"))
                SilhouetteShape(silhouette: s, keystoneOnly: true).fill(Color("AccentBrass")).widgetAccentable()
            } else {
                Image(systemName: "building.columns").font(.largeTitle).foregroundStyle(Color("LabelTertiary"))
            }
        }
    }

    private var status: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.solved ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(entry.solved ? Color("StateSuccess") : Color("LabelTertiary"))
            Text(entry.solved ? "widget.solved" : "widget.notSolved")
                .foregroundStyle(Color("LabelSecondary"))
        }
        .font(.caption2.weight(.semibold))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("widget.daily").font(.system(size: 11, weight: .regular, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Color("LabelTertiary"))
                Spacer()
                Text(verbatim: "\(entry.streak)").font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color("AccentBrass")).widgetAccentable()
            }
            art.frame(maxWidth: .infinity, maxHeight: .infinity)
            status
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            art.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text("widget.daily").font(.system(size: 11, weight: .regular, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Color("LabelTertiary"))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(entry.streak)").font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color("AccentBrass")).widgetAccentable()
                    Text("widget.days").font(.subheadline).foregroundStyle(Color("LabelSecondary"))
                }
                if let par = entry.day?.par {
                    Text("widget.par \(par)").font(.caption).foregroundStyle(Color("LabelSecondary"))
                }
                Spacer(minLength: 0)
                status
            }
            .frame(maxWidth: 130, alignment: .leading)
        }
    }
}

@main
struct DailyWidgetBundle: WidgetBundle {
    var body: some Widget { DailyWidget() }
}
