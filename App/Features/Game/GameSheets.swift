import BalanceCore
import SwiftUI

/// Pause: Resume, Restart, Hint (rewarded), Sound/Haptics, Back to Map. The only way out mid-level.
struct PauseSheet: View {
    @Environment(AppModel.self) private var app
    let session: GameSession
    let swap: (GameLaunch?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("pause.title").font(.title2.bold())
                    Spacer()
                    Text("pause.sub \(Copy.shortLevel(session.level, mode: session.launch.mode)) \(session.moveLog.count) \(session.level.goal.moveBudget)")
                        .font(.footnote).foregroundStyle(Palette.text2).monospacedDigit()
                }
                .padding(.horizontal, 4).padding(.bottom, 4)
                Button { session.overlay = nil } label: {
                    Label("pause.resume", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    session.overlay = nil
                    session.retry()
                } label: {
                    Label("pause.restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                RewardedButton(title: "pause.hint", tag: app.ads.rewardedEnabled ? "ad.tag" : "ad.offline.tag",
                               dimmed: !app.ads.rewardedEnabled) {
                    session.overlay = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        session.openHint()
                    }
                }
                VStack(spacing: 0) {
                    ToggleRow(icon: "speaker.wave.2", title: "pause.sound", isOn: Binding(
                        get: { app.progress.settings.sound },
                        set: { v in app.progress.update { $0.sound = v }; app.applySettings() }))
                    Divider().overlay(Palette.line)
                    ToggleRow(icon: "waveform", title: "pause.haptics", isOn: Binding(
                        get: { app.progress.settings.haptics },
                        set: { v in app.progress.update { $0.haptics = v }; app.applySettings() }))
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 1))
                .padding(.top, 4)
                Button {
                    session.overlay = nil
                    swap(nil)
                } label: {
                    Label(session.launch.isCampaign ? "common.backToMap" : "common.backToMenu", systemImage: "map")
                        .font(.body).foregroundStyle(Palette.text2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .keystoneSheet(height: 560)
    }
}

struct ToggleRow: View {
    let icon: String
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title).font(.body)
            } icon: {
                Image(systemName: icon).foregroundStyle(Palette.text2)
            }
        }
        .tint(Palette.jade)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }
}

/// Confirmation card before the rewarded ad ("what do I get"), and the no-fill variant (free).
struct HintSheet: View {
    @Environment(AppModel.self) private var app
    let session: GameSession
    let noAd: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "lightbulb")
                .font(.system(size: 26))
                .foregroundStyle(noAd ? Palette.jade : Palette.accent)
                .frame(width: 56, height: 56)
                .background(noAd ? Palette.jadeSoft : Palette.accentSoft, in: Circle())
            if noAd {
                Text("hint.noAd.title").font(.title2.bold())
                Text("hint.noAd.body").font(.body).foregroundStyle(Palette.text2)
                Button { session.freeHint() } label: { Label("hint.show", systemImage: "lightbulb") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
            } else {
                Text("hint.title").font(.title2.bold())
                Text(app.ads.adsRemoved ? "hint.body.free" : "hint.body").font(.body).foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if app.ads.rewardedEnabled {
                    Button { Task { await session.watchHint() } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill").font(.system(size: 15))
                            Text(app.ads.adsRemoved ? "hint.show" : "hint.watch")
                            if !app.ads.adsRemoved {
                                Text("hint.adLength").font(Typo.mono(10)).tracking(1)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.foreground, lineWidth: 1))
                                    .opacity(0.7)
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
                } else {
                    Label("ad.offline", systemImage: "wifi.slash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 6)
                }
            }
            Button { session.overlay = nil } label: { Text("hint.notNow") }
                .buttonStyle(SecondaryButtonStyle())
            if !noAd {
                Text("hint.optional").font(.footnote).foregroundStyle(Palette.text3)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .keystoneSheet(height: noAd ? 380 : 470)
    }
}

/// Still standing, goal not met, budget spent. A gentle sibling of the collapse screen.
struct OutOfMovesCard: View {
    @Environment(AppModel.self) private var app
    let session: GameSession
    let swap: (GameLaunch?) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.scrim.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Kicker(text: Text("outOfMoves.kicker"))
                Text("outOfMoves.title").font(.title2.bold())
                Text(bodyText).font(.body).foregroundStyle(Palette.text2)
                Button { session.retry() } label: { Label("collapse.retry", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
                Button { session.undo() } label: { Label("outOfMoves.undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { Task { await session.leave(.map, swap: swap) } } label: {
                    Text(session.launch.isCampaign ? "common.backToMap" : "common.backToMenu")
                        .foregroundStyle(Palette.text2).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .background(Palette.sheet, in: UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 30) }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var bodyText: String {
        if session.level.goal.type == .dropOnlyTarget { return String(localized: "outOfMoves.body.drop") }
        let done = GoalRules.removedTargetCount(goal: session.level.goal, removed: session.moveLog.removedIds)
        return String(localized: "outOfMoves.body \(done) \(session.level.goal.effectiveRequiredCount)")
    }
}

/// Tutorial chip: one sentence, Skip. Shown on the first three levels.
struct TutorialOverlay: View {
    let kind: Int
    let skip: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Palette.accent)
            Text(text).font(.system(size: 15, weight: .medium)).lineLimit(2).minimumScaleFactor(0.85)
            Rectangle().fill(Palette.line2).frame(width: 1, height: 20)
            Button(action: skip) {
                Text("tut.skip").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10).frame(minHeight: 44)
            }
        }
        .padding(.leading, 14).padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(Palette.hud, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .transition(.opacity)
    }

    private var icon: String {
        switch kind {
        case 1: return "hand.tap"
        case 2: return "exclamationmark.triangle"
        default: return "arrow.down.to.line"
        }
    }

    private var text: LocalizedStringKey {
        switch kind {
        case 1: return "tut.1"
        case 2: return "tut.2"
        default: return "tut.3"
        }
    }
}
