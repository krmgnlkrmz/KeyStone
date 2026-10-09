import BalanceCore
import SpriteKit
import SwiftUI

/// Level Clear panel. The standing structure (with dimension lines) stays in the play area above,
/// hosted by the same SpriteView, so the scene is never presented twice.
struct LevelResultView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: GameSession
    let swap: (GameLaunch?) -> Void
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Kicker(text: Text(kicker), color: Palette.jade)
                Text(session.level.goal.type == .dropOnlyTarget ? "success.title.drop" : "success.title")
                    .font(Typo.title1)
                StarRow(earned: session.earnedStars, shown: shown)
                Text("success.moves \(session.moveLog.count) \(session.bestMoves)")
                    .font(.subheadline).foregroundStyle(Palette.text2).monospacedDigit()
                if session.completion?.newBest == true, session.completion?.previousStars ?? 0 > 0 {
                    Text("success.newBest").font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            VStack(spacing: 10) {
                Button { Task { await session.leave(session.hasNext ? .next : .map, swap: swap) } } label: {
                    HStack(spacing: 8) {
                        Text(nextTitle)
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                if session.earnedStars < 3 && session.tension.isUsable {
                    RewardedButton(title: "success.perfect", tag: app.ads.rewardedEnabled ? "ad.tag" : "ad.offline.tag",
                                   dimmed: !app.ads.rewardedEnabled) {
                        guard app.ads.rewardedEnabled else { app.showToast(String(localized: "hint.offline.toast")); return }
                        Task { await session.showPerfectSolution() }
                    }
                }
                HStack(spacing: 10) {
                    Button { session.retry() } label: { Label("success.replay", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { Task { await session.leave(.map, swap: swap) } } label: {
                        Label(session.launch.isCampaign ? "success.map" : "success.menu", systemImage: "map")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .task { await revealStars() }
    }

    private var kicker: LocalizedStringKey {
        switch session.launch.mode {
        case .campaign: return "success.kicker \(session.level.index)"
        case .daily: return "success.kicker.daily"
        case .endless: return "success.kicker.endless"
        }
    }

    private var nextTitle: LocalizedStringKey {
        switch session.launch.mode {
        case .campaign: return session.hasNext ? "success.next" : "common.backToMap"
        case .daily: return "common.backToMenu"
        case .endless: return "success.nextEndless"
        }
    }

    /// Stars fill one by one (0.28 s stagger) with a success haptic and a chime each.
    private func revealStars() async {
        try? await Task.sleep(for: .milliseconds(450))
        for i in 0..<session.earnedStars {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.6)) { shown = i + 1 }
            app.haptics.star()
            app.sound.play(.chime, volume: 0.6)
            try? await Task.sleep(for: .milliseconds(280))
        }
    }
}

struct StarRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let earned: Int
    let shown: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < shown ? "star.fill" : "star")
                    .font(.system(size: 40))
                    .foregroundStyle(i < shown ? Palette.accent : Palette.text3)
                    .scaleEffect(i < shown || reduceMotion ? 1 : 0.85)
                    .transition(.scale)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("a11y.stars \(earned)"))
    }
}
