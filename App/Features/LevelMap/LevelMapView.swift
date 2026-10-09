import BalanceCore
import SwiftUI

/// Level Map: regions with sticky headers, three-column grid of cells, progress at the top.
/// A region opens once 70 % of the previous one is done; inside an open region every level is playable.
struct LevelMapView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let catalog = app.catalog
        let done = app.progress.completedIds
        let curatedIds = Set(catalog.curated.map(\.id))
        let doneCount = done.intersection(curatedIds).count
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("map.progress \(doneCount) \(catalog.curated.count)")
                    Spacer()
                    Text(verbatim: "\(app.progress.totalStars) ★")
                }
                .font(.footnote).foregroundStyle(Palette.text2).monospacedDigit()
                ProgressView(value: Double(doneCount), total: Double(max(1, catalog.curated.count)))
                    .tint(Palette.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)

            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(catalog.regions.enumerated()), id: \.offset) { index, region in
                    let unlocked = app.isRegionUnlocked(index)
                    Section {
                        if unlocked || index == 0 {
                            RegionGrid(levels: region.levels, unlocked: unlocked)
                        } else {
                            LockedRegionCard(index: index)
                        }
                    } header: {
                        RegionHeaderView(region: region.region, levels: region.levels, unlocked: unlocked)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ScreenBackground())
        .navigationTitle(Text("map.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !app.ads.adsRemoved {
                    RemoveAdsChip()
                }
                Button { app.router.sheet = .settings } label: {
                    Image(systemName: "gearshape").foregroundStyle(Palette.accent)
                }
                .accessibilityLabel(Text("menu.settings"))
                .accessibilityIdentifier("map.settings")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { BannerSlot() }
    }
}

struct RemoveAdsChip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button { Task { await app.store.purchase() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.slash").scaledFont(13, relativeTo: .footnote)
                Text("map.removeAds").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Palette.text2)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
        }
        .disabled(app.store.state == .purchasing)
        .accessibilityHint(Text(app.store.displayPrice.map { String(localized: "store.price \($0)") } ?? String(localized: "store.priceUnknown")))
    }
}

struct RegionHeaderView: View {
    @Environment(AppModel.self) private var app
    let region: Region
    let levels: [Level]
    let unlocked: Bool

    var body: some View {
        let stars = levels.reduce(0) { $0 + app.progress.stars($1.id) }
        AdaptiveStack {
            Text(Copy.zoneTitle(region))
                .scaledFont(12, design: .monospaced, relativeTo: .caption).tracking(1.5)
                .foregroundStyle(unlocked ? Palette.text : Palette.text3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1) // the region's name wins the row's width over the star count
            Spacer(minLength: 0)
            if unlocked {
                Text(verbatim: "\(levels.first?.index ?? 0)–\(levels.last?.index ?? 0) · \(stars) / \(levels.count * 3) ★")
                    .font(.footnote).foregroundStyle(Palette.text2).monospacedDigit()
            } else {
                Label {
                    Text(verbatim: "\(levels.first?.index ?? 0)–\(levels.last?.index ?? 0)")
                } icon: {
                    Image(systemName: "lock.fill").font(.system(size: 12))
                }
                .font(.footnote).foregroundStyle(Palette.text3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
        .background(.ultraThinMaterial)
        .background(Palette.hud)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct RegionGrid: View {
    @Environment(AppModel.self) private var app
    let levels: [Level]
    let unlocked: Bool

    var body: some View {
        let done = app.progress.completedIds
        let nextId = levels.first { !done.contains($0.id) }?.id
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(levels) { level in
                LevelCellView(level: level,
                              state: !unlocked ? .locked : done.contains(level.id) ? .done(app.progress.stars(level.id))
                                  : (level.id == nextId ? .next : .open))
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 20, trailing: 16))
    }
}

private struct LockedRegionCard: View {
    @Environment(AppModel.self) private var app
    let index: Int

    var body: some View {
        let missing = UnlockRules.completionsMissing(toUnlock: index, regions: app.regionLevelIds, completed: app.progress.completedIds)
        let previous = app.catalog.regions[index - 1].region
        VStack(alignment: .leading, spacing: 3) {
            Text("map.zoneLocked \(missing)").font(.body.weight(.semibold))
            Text("map.zoneLockedSub \(Copy.regionName(previous))").font(.footnote).foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
        .accessibilityElement(children: .combine)
    }
}
