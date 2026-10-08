import BalanceCore
import BalancePhysics
import SpriteKit
import SwiftUI

/// Full-screen game cover: play area + HUD, and the end states (collapse replay, clear, out of moves)
/// as states of the same cover, so an interstitial never stacks on top of the game.
struct GameContainerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var session: GameSession?
    let launch: GameLaunch

    var body: some View {
        ZStack {
            ScreenBackground()
            if let session {
                GameScreen(session: session, swap: swap)
                    .id(session.launch.id)
            }
            if app.curtain {
                // Interstitial curtain: stays up across the swap to the next level.
                Palette.background.ignoresSafeArea().transition(.opacity)
            }
        }
        .statusBarHidden(false)
        .interactiveDismissDisabled()
        .onAppear { if session == nil { load(launch) } }
        .onChange(of: colorScheme) { _, scheme in session?.scene.palette = Palette.scene(dark: scheme == .dark) }
        .onAppear { app.sound.ducked = true }
        .onDisappear {
            app.sound.ducked = false
            session?.teardown()
        }
    }

    private func load(_ launch: GameLaunch) {
        guard let level = app.catalog.level(id: launch.levelId) else { return }
        let s = GameSession(launch: launch, level: level, app: app, dark: colorScheme == .dark, reduceMotion: reduceMotion)
        session?.teardown()
        session = s
        s.start()
    }

    /// Next level (in place, behind the curtain) or back to the map/menu (dismiss).
    private func swap(_ next: GameLaunch?) {
        if let next {
            load(next)
        } else {
            app.router.game = nil
        }
    }
}

private struct GameScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var session: GameSession
    let swap: (GameLaunch?) -> Void
    @State private var playFrame: CGRect = .zero

    var body: some View {
        ZStack {
            switch session.phase {
            case .collapsed:
                if let info = session.collapse {
                    CollapseReplayView(session: session, info: info, swap: swap)
                        .transition(.opacity)
                }
            default:
                playLayer
            }
            if let text = app.toast {
                VStack { ToastView(text: text).padding(.top, 140); Spacer() }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .sheet(item: $session.overlay) { overlay in
            switch overlay {
            case .pause: PauseSheet(session: session, swap: swap)
            case .hint: HintSheet(session: session, noAd: false)
            case .hintNoAd: HintSheet(session: session, noAd: true)
            }
        }
    }

    private var playLayer: some View {
        ZStack {
            LinearGradient(colors: [.clear, Palette.background2], startPoint: UnitPoint(x: 0.5, y: 0.7), endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                if session.phase != .won {
                    GameHUDView(session: session)
                } else {
                    Spacer().frame(height: 24)
                }
                ZStack {
                    SpriteView(scene: session.scene, preferredFramesPerSecond: 60, options: [.allowsTransparency, .ignoresSiblingOrder])
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { playFrame = geo.frame(in: .named("game")) }
                                    .onChange(of: geo.frame(in: .named("game"))) { _, f in playFrame = f }
                            }
                        )
                        .accessibilityHidden(true)
                    PieceAccessibilityLayer(session: session)
                    if AppConfig.isUITest {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityElement()
                            .accessibilityLabel(Text(verbatim: session.lastSupportEvent.isEmpty ? "none" : session.lastSupportEvent))
                            .accessibilityIdentifier("debug.supportEvent")
                            .allowsHitTesting(false)
                    }
                    Color.black.opacity(session.collapsing && session.phase == .evaluating ? (reduceMotion ? 0.12 : 0.15) : 0)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.2), value: session.collapsing)
                }
                if session.phase == .won {
                    LevelResultView(session: session, swap: swap)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    GameBottomBar(session: session, playFrame: playFrame)
                }
            }
            if session.phase == .outOfMoves {
                OutOfMovesCard(session: session, swap: swap)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(.named("game"))
    }
}

/// Invisible VoiceOver elements laid over each piece (SpriteKit nodes are not accessibility elements).
private struct PieceAccessibilityLayer: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let session: GameSession

    var body: some View {
        if voiceOver || AppConfig.isUITest, session.phase == .playing {
            let _ = session.layoutVersion
            ZStack(alignment: .topLeading) {
                ForEach(session.scene.structure?.presentIds ?? [], id: \.self) { id in
                    if let frame = session.scene.viewFrame(of: id), let label = session.accessibilityLabel(for: id) {
                        Color.clear
                            .frame(width: max(frame.width, 44), height: max(frame.height, 44))
                            .contentShape(Rectangle())
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityElement()
                            .accessibilityLabel(label)
                            .accessibilityIdentifier("piece.\(id)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(Text(session.selectedId == id ? "a11y.hint.remove" : "a11y.hint.select"))
                            .accessibilityAction { session.scene.activate(id) }
                            .onTapGesture { session.scene.activate(id) }
                    }
                }
                // Support spots: VoiceOver (and the UI soak test) place a strut by choosing a spot, not by dragging.
                // Spots can sit a few points apart; each one gets only its own slice so no spot covers a neighbour.
                let spots = session.supportSpots
                let centers = spots.map { session.scene.viewPoint(fromScene: CGPoint(x: $0.x, y: ($0.bottomY + $0.topY) / 2)) }
                ForEach(Array(spots.enumerated()), id: \.element.token) { i, spot in
                    let center = centers[i]
                    Color.clear
                        .frame(width: Self.spotWidth(at: i, centers: centers), height: 44)
                        .contentShape(Rectangle())
                        .position(center)
                        .accessibilityElement()
                        .accessibilityLabel(Text(Copy.supportSpot(spot, index: i, of: spots.count, level: session.level)))
                        .accessibilityIdentifier("support.\(spot.token)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("a11y.supportSpot.hint"))
                        .accessibilityAction { session.placeSupport(spot) }
                        .onTapGesture { session.placeSupport(spot) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 44 pt wide unless a neighbouring spot (at about the same height) is closer; then the gap, so they meet halfway.
    private static func spotWidth(at i: Int, centers: [CGPoint]) -> CGFloat {
        var width: CGFloat = 44
        for (j, other) in centers.enumerated() where j != i && abs(other.y - centers[i].y) < 44 {
            width = min(width, abs(other.x - centers[i].x))
        }
        return max(width, 4)
    }
}
