import BalanceCore
import SwiftUI

/// Top HUD: pause · level + goal · moves · undo. Fixed size (exempt from Dynamic Type; the goal
/// wraps to two lines instead of truncating). Left-Hand Mode swaps undo to the left.
struct GameHUDView: View {
    @Environment(AppModel.self) private var app
    let session: GameSession

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if app.progress.settings.leftHanded { undoButton } else { pauseButton }
                VStack(spacing: 3) {
                    Text(session.kicker)
                        .font(Typo.mono(11)).tracking(1.5)
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                    Text(session.goalText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(session.moveLog.count)").font(Typo.counter(28)).foregroundStyle(Palette.text)
                        Text(verbatim: " / \(session.level.goal.moveBudget)").font(Typo.counter(18)).foregroundStyle(Palette.text3)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    Text(session.progressText)
                        .font(Typo.mono(10)).tracking(1.5)
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("a11y.moves \(session.moveLog.count) \(session.level.goal.moveBudget)"))
                .accessibilityValue(session.progressText)
                if app.progress.settings.leftHanded { pauseButton } else { undoButton }
            }
            .padding(.horizontal, 12)
            .frame(height: 60)

            ZStack {
                if let hint = session.hint, !session.demo {
                    HintChip(hint: hint, support: SupportToken.isSupport(hint.token))
                } else if session.demo {
                    Chip(icon: "play.fill", tint: Palette.jade) { Text("demo.chip") }
                } else if session.tutorialVisible, let kind = session.level.tutorial, session.phase == .playing {
                    TutorialOverlay(kind: kind) { session.dismissTutorial() }
                } else if session.isSettling && session.phase == .evaluating {
                    SettlingIndicator()
                }
            }
            .frame(height: 44)
            .animation(.easeOut(duration: 0.3), value: session.hint)
        }
        .padding(.top, 4)
    }

    private var pauseButton: some View {
        HUDCircleButton(systemImage: "pause.fill", label: "hud.pause") {
            if session.phase == .playing || session.phase == .outOfMoves { session.overlay = .pause }
        }
    }

    private var undoButton: some View {
        HUDCircleButton(systemImage: "arrow.uturn.backward", label: "hud.undo", dimmed: !session.canUndo) { session.undo() }
            .disabled(!session.canUndo)
    }
}

struct Chip<Label: View>: View {
    let icon: String
    var tint: Color = Palette.accent
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 16))
            label().font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Palette.hud, in: Capsule())
        .overlay(Capsule().strokeBorder(tint, lineWidth: 1))
    }
}

/// "Critical piece · 5 s" with a draining ring.
private struct HintChip: View {
    let hint: GameSession.Hint
    let support: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = max(0, hint.endsAt.timeIntervalSince(ctx.date))
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Palette.line2, lineWidth: 2.5)
                    Circle().trim(from: 0, to: left / 5).stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)
                Text(support ? "hint.active.support" : "hint.active").font(.system(size: 15, weight: .semibold))
                Text("hint.seconds \(Int(left.rounded(.up)))")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text2)
            }
            .padding(.leading, 12).padding(.trailing, 16)
            .frame(height: 44)
            .background(Palette.hud, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.accent, lineWidth: 1))
        }
    }
}

/// Thin "the structure is settling" line while a move is evaluated.
private struct SettlingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        Capsule()
            .fill(Palette.line)
            .frame(width: 88, height: 2)
            .overlay(alignment: .leading) {
                Capsule().fill(Palette.accent).frame(width: 34, height: 2)
                    .offset(x: reduceMotion ? 27 : (phase ? 88 : -34))
            }
            .clipShape(Capsule())
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { phase = true }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("hud.settling"))
    }
}

/// Bottom bar: Support pill (drag into place) and the Hint pill. Left-Hand Mode mirrors it.
struct GameBottomBar: View {
    @Environment(AppModel.self) private var app
    let session: GameSession
    let playFrame: CGRect
    @State private var dragging = false
    @State private var lastValid: Bool?

    var body: some View {
        HStack(spacing: 12) {
            if app.progress.settings.leftHanded {
                support
                Spacer(minLength: 0)
                hint
            } else {
                hint
                Spacer(minLength: 0)
                support
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(height: 76)
        .opacity(session.phase == .playing || session.phase == .evaluating ? 1 : 0)
    }

    @ViewBuilder private var support: some View {
        if session.level.supportsAllowed > 0 {
            let available = session.supportsLeft > 0 && session.interactive
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.forward")
                    .rotationEffect(.degrees(-90))
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.accent)
                Text(dragging ? "hud.placing" : "hud.support").font(.system(size: 15, weight: .semibold))
                Text(verbatim: "\(session.supportsLeft)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(Palette.accentSoft, in: Capsule())
            }
            .padding(.leading, 16).padding(.trailing, 8)
            .frame(height: 52)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(dragging ? Palette.accent : Palette.line,
                                             style: StrokeStyle(lineWidth: 1.5, dash: dragging ? [5, 3] : [])))
            .shadow(color: dragging ? Palette.accentSoft : .clear, radius: 6)
            .opacity(available ? 1 : 0.45)
            .gesture(dragGesture, including: available ? .all : .none)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("hud.support"))
            .accessibilityValue(Text(verbatim: "\(session.supportsLeft)"))
            .accessibilityHint(Text("a11y.support.hint"))
            .accessibilityAction(named: Text("a11y.support.placeBest")) { placeBestSupportForAccessibility() }
        }
    }

    private var hint: some View {
        Button { session.openHint() } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 1.5))
                Text("hud.hint").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                AdTag(text: app.ads.rewardedEnabled ? "ad.tag" : "ad.offline.tag")
            }
            .padding(.leading, 8).padding(.trailing, 12)
            .frame(height: 52)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
            .opacity(app.ads.rewardedEnabled && session.interactive ? 1 : 0.45)
        }
        .buttonStyle(PressPlain())
        .disabled(!session.interactive)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("game"))
            .onChanged { value in
                dragging = true
                let local = CGPoint(x: value.location.x - playFrame.minX, y: value.location.y - playFrame.minY)
                let placement = session.scene.showSupportGhost(atViewPoint: local)
                let valid = placement?.isValid
                if valid == true && lastValid != true { app.haptics.select() }
                lastValid = valid
            }
            .onEnded { value in
                dragging = false
                lastValid = nil
                let local = CGPoint(x: value.location.x - playFrame.minX, y: value.location.y - playFrame.minY)
                let placement = session.scene.showSupportGhost(atViewPoint: local)
                session.scene.hideSupportGhost()
                if let placement, placement.isValid {
                    session.placeSupport(placement)
                } else if placement != nil {
                    session.rejectSupport()
                }
            }
    }

    /// VoiceOver can't drag: offer the first valid position under the goal's first target.
    private func placeBestSupportForAccessibility() {
        let candidates = SupportGeometry.candidates(level: session.level, removed: session.moveLog.removedIds,
                                                    supports: session.scene.placedSupports)
        if let first = candidates.first { session.placeSupport(first) } else { session.rejectSupport() }
    }
}
