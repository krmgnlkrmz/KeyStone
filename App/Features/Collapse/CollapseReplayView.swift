import BalanceCore
import BalancePhysics
import SpriteKit
import SwiftUI

/// Collapse Replay: the recorded fall in slow motion, scrubbable, with the piece that gave way marked.
/// Reduce Motion: three still frames instead of playback, no shake.
struct CollapseReplayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: GameSession
    let info: GameSession.CollapseInfo
    let swap: (GameLaunch?) -> Void

    @State private var scene: ReplayScene?
    @State private var time: Double = 0
    @State private var playing = true
    @State private var speed: Double = 0.25
    @State private var replaySize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
            ZStack {
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
                        .accessibilityElement()
                        .accessibilityLabel(Text("collapse.a11y \(blameText ?? "")"))
                    if let blame = blameText, let point = scene.blamedViewPoint() {
                        BlameCallout(text: blame, target: point, size: replaySize)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(GeometryReader { g in Color.clear.onAppear { replaySize = g.size }.onChange(of: g.size) { _, s in replaySize = s } })
            .frame(maxHeight: .infinity)
            VStack(spacing: 10) {
                if reduceMotion {
                    StillFrames(scene: scene, moveNumber: info.moveNumber, selected: time) { t in
                        time = t
                        scene?.seek(to: t)
                    }
                } else {
                    ReplayScrubBar(time: $time, duration: info.recording.duration, playing: $playing, speed: $speed,
                                   moveNumber: info.moveNumber) { t in
                        scene?.pause()
                        playing = false
                        scene?.seek(to: t)
                    }
                }
                Button { session.retry() } label: { Label("collapse.retry", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(PrimaryButtonStyle())
                RewardedButton(title: "collapse.lastMove", tag: app.ads.rewardedEnabled ? "ad.tag" : "ad.offline.tag",
                               dimmed: !app.ads.rewardedEnabled) {
                    guard app.ads.rewardedEnabled else { app.showToast(String(localized: "hint.offline.toast")); return }
                    Task { await session.backToLastMove() }
                }
                Button { Task { await session.leave(.map, swap: swap) } } label: {
                    Text(session.launch.isCampaign ? "common.backToMap" : "common.backToMenu")
                        .foregroundStyle(Palette.text2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .onAppear(perform: makeScene)
        .onChange(of: playing) { _, p in p ? scene?.play() : scene?.pause() }
        .onChange(of: speed) { _, s in scene?.speedFactor = s }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Label { Kicker(text: Text("collapse.kicker")) } icon: {
                    Image(systemName: "timer").font(.system(size: 13)).foregroundStyle(Palette.text3)
                }
                Text(session.level.goal.type == .dropOnlyTarget ? "collapse.title.drop" : "collapse.title")
                    .font(Typo.title1)
                Text("collapse.sub").font(.subheadline).foregroundStyle(Palette.text2)
            }
            Spacer()
            Text(Copy.shortLevel(session.level, mode: session.launch.mode))
                .font(.footnote).foregroundStyle(Palette.text3).padding(.bottom, 4)
        }
    }

    private var blameText: String? {
        guard let id = info.culpritId, let piece = session.level.piece(id) ?? info.recording.extraPieces.first(where: { $0.id == id }) else { return nil }
        return Copy.blame(piece, lostBalance: info.lostBalance)
    }

    private func makeScene() {
        guard scene == nil else { return }
        let s = ReplayScene(level: session.level, recording: info.recording, size: CGSize(width: 390, height: 480),
                            palette: Palette.scene(dark: colorScheme == .dark), reduceMotion: reduceMotion)
        s.speedFactor = speed
        s.onTimeChange = { t in
            time = t
            if t >= info.recording.duration - 1e-6 { playing = false }
        }
        if reduceMotion {
            s.seek(to: s.stillFrameTimes.last ?? 0)
            time = s.time
            playing = false
        } else {
            s.play()
        }
        scene = s
    }
}

/// Play/pause, scrub, time and move, 0.25× / 0.5×.
struct ReplayScrubBar: View {
    @Environment(AppModel.self) private var app
    @Binding var time: Double
    let duration: Double
    @Binding var playing: Bool
    @Binding var speed: Double
    let moveNumber: Int
    let seek: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { playing.toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.text)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface2, in: Circle())
            }
            .accessibilityLabel(Text(playing ? "replay.pause" : "replay.play"))
            VStack(spacing: 6) {
                GeometryReader { g in
                    let pct = duration > 0 ? min(1, time / duration) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.surface2).frame(height: 4)
                        Capsule().fill(Palette.text).frame(width: g.size.width * pct, height: 4)
                        Circle().fill(Palette.text).frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: g.size.width * pct - 8)
                    }
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let f = min(1, max(0, v.location.x / max(1, g.size.width)))
                        let t = f * duration
                        if Int(t * 4) != Int(time * 4) { app.haptics.select() }
                        seek(t)
                        time = t
                    })
                }
                .frame(height: 28)
                .accessibilityElement()
                .accessibilityLabel(Text("replay.position"))
                .accessibilityValue(Text("replay.time \(time, format: .number.precision(.fractionLength(1)))"))
                .accessibilityAdjustableAction { dir in
                    let step = duration / 10
                    let t = min(duration, max(0, time + (dir == .increment ? step : -step)))
                    seek(t); time = t
                }
                HStack {
                    Text(verbatim: String(format: "%.1f s / %.1f s", time, duration))
                    Spacer()
                    Text("replay.move \(moveNumber)")
                }
                .scaledFont(10, design: .monospaced, relativeTo: .caption2).foregroundStyle(Palette.text3)
            }
            HStack(spacing: 0) {
                speedButton(0.25, label: "0.25×")
                speedButton(0.5, label: "0.5×")
            }
            .padding(2)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func speedButton(_ value: Double, label: String) -> some View {
        Button { speed = value } label: {
            Text(verbatim: label).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(speed == value ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(speed == value ? .isSelected : [])
    }
}

/// Reduce Motion: Before / Move N / Collapse stills.
private struct StillFrames: View {
    let scene: ReplayScene?
    let moveNumber: Int
    let selected: Double
    let pick: (Double) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array((scene?.stillFrameTimes ?? []).enumerated()), id: \.offset) { i, t in
                    Button { pick(t) } label: {
                        Text(label(i))
                            .font(.caption).foregroundStyle(Palette.text2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(abs(selected - t) < 0.01 ? Palette.text : .clear, lineWidth: 1.5))
                    }
                }
            }
            Label("collapse.rm", systemImage: "figure.walk.motion")
                .font(.caption).foregroundStyle(Palette.text2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func label(_ i: Int) -> LocalizedStringKey {
        switch i {
        case 0: return "collapse.still.before"
        case 1: return "collapse.still.move \(moveNumber)"
        default: return "collapse.still.collapse"
        }
    }
}

/// "This post couldn't carry the load." tag with an arrow to the piece's starting position.
struct BlameCallout: View {
    let text: String
    let target: CGPoint
    let size: CGSize

    var body: some View {
        let leftSide = target.x > size.width / 2
        let tagWidth: CGFloat = 172
        let tagOrigin = CGPoint(x: leftSide ? 14 : size.width - tagWidth - 14, y: 8)
        let arrowStart = CGPoint(x: tagOrigin.x + (leftSide ? tagWidth - 30 : 30), y: tagOrigin.y + 56)
        let arrowEnd = CGPoint(x: target.x + (leftSide ? -14 : 14), y: max(arrowStart.y + 20, target.y - 22))
        ZStack(alignment: .topLeading) {
            Arrow(from: arrowStart, to: arrowEnd)
                .stroke(Palette.danger, lineWidth: 1.5)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(width: tagWidth, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.danger, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
                .offset(x: tagOrigin.x, y: tagOrigin.y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct Arrow: Shape {
    let from: CGPoint
    let to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        for d in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
            p.move(to: to)
            p.addLine(to: CGPoint(x: to.x + cos(angle + d) * 9, y: to.y + sin(angle + d) * 9))
        }
        return p
    }
}
