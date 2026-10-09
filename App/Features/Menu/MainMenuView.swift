import BalanceCore
import SwiftUI

/// Main Menu: lockup, breathing structure, Continue card, and the list (Levels, Daily, Endless, Settings).
struct MainMenuView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            ScreenBackground()
            StructureSilhouetteView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 150)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    HUDCircleButton(systemImage: app.progress.settings.sound ? "speaker.wave.2" : "speaker.slash",
                                    label: "menu.sound", dimmed: !app.progress.settings.sound) {
                        app.progress.update { $0.sound.toggle() }
                        app.applySettings()
                    }
                    HUDCircleButton(systemImage: "trophy", label: "menu.gameCenter") {
                        if app.achievements.isAuthenticated { app.achievements.showDashboard() }
                        else { app.showToast(String(localized: "menu.gameCenter.off")) }
                    }
                }
                .padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        KeystoneGlyph().fill(Palette.accent).frame(width: 30, height: 30)
                        Text("app.name").scaledFont(34, weight: .bold, relativeTo: .largeTitle).tracking(-0.6)
                    }
                    Text("menu.tagline").font(.subheadline).foregroundStyle(Palette.text2)
                }
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 20)
                continueCard
                    .padding(.bottom, 12)
                menuList
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { BannerSlot() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { app.noteMenuShown() }
        .overlay {
            if AppConfig.exposesTestProbes, let seconds = app.launchToMenu {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: String(format: "%.3f", seconds)))
                    .accessibilityIdentifier("debug.launch")
                    .allowsHitTesting(false)
            }
        }
    }

    private var continueCard: some View {
        let next = app.nextCampaignLevel
        return Button {
            if let next { app.play(next) }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.progress.completedIds.isEmpty ? "menu.start" : "menu.continue")
                        .font(.caption.weight(.bold)).tracking(1.4).opacity(0.72)
                    Text(next.map { Copy.levelTitle($0, mode: .campaign) } ?? String(localized: "menu.noLevels"))
                        .font(.title2.weight(.semibold))
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.fill")
                    .font(.system(size: 18))
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.14), in: Circle())
            }
            .foregroundStyle(Palette.onAccent)
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 16))
            .frame(minHeight: 84)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 15, y: 10)
        }
        .buttonStyle(PressPlain())
        .disabled(next == nil)
    }

    private var menuList: some View {
        VStack(spacing: 0) {
            MenuRow(icon: "map", title: "menu.levels",
                    value: Text(verbatim: "\(app.progress.completedIds.intersection(app.catalog.curated.map(\.id)).count) / \(app.catalog.curated.count)"), identifier: "menu.levels") {
                app.router.path.append(.map)
            }
            divider
            MenuRow(icon: "calendar", title: "menu.daily", value: dailyValue, identifier: "menu.daily") {
                app.router.sheet = .daily
            }
            divider
            MenuRow(icon: "infinity", title: "menu.endless", value: Text("menu.endless.value"), identifier: "menu.endless") {
                app.router.path.append(.endless)
            }
            divider
            MenuRow(icon: "gearshape", title: "menu.settings", value: nil, identifier: "menu.settings") {
                app.router.sheet = .settings
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }

    private var dailyValue: Text {
        let date = Copy.shortDate(app.todayKey)
        let streak = app.displayStreak
        if app.dailySolvedToday { return Text("menu.daily.solved \(streak)") }
        return streak > 0 ? Text("menu.daily.value \(date) \(streak)") : Text(verbatim: date)
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 52)
    }
}

struct MenuRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: Text?
    /// Stable id for UI tests (labels change with language and text size).
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).scaledFont(20, relativeTo: .body).foregroundStyle(Palette.accent).frame(minWidth: 24)
                Text(title).font(.body).foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                if let value {
                    value.font(.subheadline).foregroundStyle(Palette.text2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                }
                Image(systemName: "chevron.right").scaledFont(14, weight: .semibold, relativeTo: .body).foregroundStyle(Palette.text3)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier(identifier)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Color.gray.opacity(0.12) : .clear)
    }
}

/// The keystone trapezoid (brand glyph).
struct KeystoneGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.22))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.06, y: r.minY + r.height * 0.22))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.78, y: r.maxY - r.height * 0.18))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.22, y: r.maxY - r.height * 0.18))
        p.closeSubpath()
        return p
    }
}

/// The menu's breathing structure: ±0.6° sway over 7 s. Static under Reduce Motion.
struct StructureSilhouetteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var sway = false

    var body: some View {
        if let level = app.catalog.curated.dropFirst(4).first ?? app.catalog.curated.first {
            SilhouetteView(silhouette: app.silhouette(for: level), color: Palette.text2, keyColor: Palette.accent)
                .frame(width: 300, height: 380)
                .opacity(colorScheme == .dark ? 0.22 : 0.28)
                .rotationEffect(.degrees(reduceMotion ? 0 : (sway ? 0.6 : -0.6)), anchor: .bottom)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { sway = true }
                }
                .allowsHitTesting(false)
        }
    }
}
