import BalanceCore
import CoreGraphics
import Foundation
import SpriteKit

/// Plays a frozen `Recording` with physics off: every node's transform is assigned from the
/// recording, so the same collapse looks identical every time, at any speed, scrubbed either way.
@MainActor
public final class ReplayScene: SKScene {
    public let level: Level
    public let recording: Recording
    public var palette: ScenePalette { didSet { if palette.isDark != oldValue.isDark { rebuild() } } }
    public let reduceMotion: Bool

    /// Playback position in seconds of recorded (physics) time.
    public private(set) var time: Double = 0
    public var isPlaying = false
    /// 0.25× or 0.5× (the slow-motion replay is the only deliberately slow motion in the app).
    public var speedFactor: Double = 0.25
    /// Called when the position changes during playback (for the scrub bar).
    public var onTimeChange: ((Double) -> Void)?

    private let world = SKNode()
    private let cameraNode = SKCameraNode()
    private var nodes: [String: SKNode] = [:]
    private var lastUpdate: TimeInterval?

    public init(level: Level, recording: Recording, size: CGSize, palette: ScenePalette, reduceMotion: Bool) {
        self.level = level
        self.recording = recording
        self.palette = palette
        self.reduceMotion = reduceMotion
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        addChild(world)
        addChild(cameraNode)
        camera = cameraNode
        rebuild()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var duration: Double { recording.duration }

    private func rebuild() {
        world.removeAllChildren()
        nodes.removeAll()
        // Ground line.
        let floorY = CGFloat(level.resolvedFloorY)
        let line = SKSpriteNode(color: palette.ground, size: CGSize(width: 4000, height: 1.5))
        line.position = CGPoint(x: 0, y: floorY - 0.75)
        world.addChild(line)
        // Where the removed piece was.
        for (id, pose) in recording.removedOrigins {
            guard var p = level.piece(id) else { continue }
            p.position = pose.position
            p.rotation = pose.rotation
            world.addChild(PieceSkin.ghost(piece: p, palette: palette, alpha: 0.4))
        }
        for id in recording.ids {
            guard let piece = level.piece(id) ?? recording.extraPieces.first(where: { $0.id == id }) else { continue }
            let node = SKNode()
            node.position = piece.position.cgPoint
            node.zRotation = CGFloat(piece.rotation)
            node.zPosition = piece.material == .brass ? 3 : 2
            PieceSkin.attach(to: node, piece: piece, palette: palette, interactive: false)
            if id == recording.culprit {
                PieceSkin.setState(.blamed, on: node, piece: piece, palette: palette, reduceMotion: reduceMotion)
                PieceSkin.setTension(.critical, on: node, piece: piece, palette: palette, reduceMotion: true)
            }
            world.addChild(node)
            nodes[id] = node
        }
        // The failing piece's ring stays at its starting pose (design kit behaviour).
        if let culprit = recording.culprit, let piece = level.piece(culprit), let start = recording.frames.first,
           let idx = recording.ids.firstIndex(of: culprit) {
            let ring = PieceSkin.ring(piece: piece, color: palette.danger, dashed: false)
            ring.position = start[idx].position.cgPoint
            ring.zRotation = CGFloat(start[idx].rotation)
            ring.zPosition = 10
            ring.name = "blameRing"
            world.addChild(ring)
        }
        seek(to: time)
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        frameCamera()
    }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        frameCamera()
    }

    /// Same framing rule as the game scene: at least the 300 × 380 design box.
    private func frameCamera() {
        guard size.width > 0, size.height > 0 else { return }
        let b = level.bounds
        var r = CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height)
        if r.width < 300 { r = r.insetBy(dx: -(300 - r.width) / 2, dy: 0) }
        if r.height < 380 { r.size.height = 380 }
        r = r.insetBy(dx: -14, dy: -18)
        cameraNode.setScale(max(r.width / size.width, r.height / size.height))
        cameraNode.position = CGPoint(x: r.midX, y: r.midY)
    }

    /// Jumps to `t` (clamped) and applies the interpolated transforms.
    public func seek(to t: Double) {
        time = min(max(0, t), duration)
        let poses = recording.poses(at: time)
        for (id, node) in nodes {
            guard let p = poses[id] else { continue }
            node.position = p.position.cgPoint
            node.zRotation = CGFloat(p.rotation)
        }
    }

    /// Current transform of a replayed body (tests, accessibility). Replay nodes never carry physics bodies.
    public func transform(of id: String) -> (position: CGPoint, rotation: CGFloat, hasPhysics: Bool)? {
        nodes[id].map { ($0.position, $0.zRotation, $0.physicsBody != nil) }
    }

    /// Fraction 0…1 for the scrub bar.
    public var progress: Double { duration > 0 ? time / duration : 0 }

    public func seek(progress: Double) { seek(to: progress * duration) }

    public func play() {
        if time >= duration - 1e-6 { seek(to: 0) }
        isPlaying = true
        lastUpdate = nil
    }

    public func pause() { isPlaying = false }

    public override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard isPlaying, let last = lastUpdate else { return }
        let dt = min(currentTime - last, 0.1)
        seek(to: time + dt * speedFactor)
        if time >= duration - 1e-6 { isPlaying = false }
        onTimeChange?(time)
    }

    /// The three still frames shown under Reduce Motion: before, the move, the collapse.
    public var stillFrameTimes: [Double] {
        let c = recording.collapseTime ?? duration * 0.35
        return [0, min(duration, c + 0.25), duration]
    }

    /// View-space position of the blamed piece's starting pose (for the SwiftUI callout).
    public func blamedViewPoint() -> CGPoint? {
        guard let culprit = recording.culprit, let idx = recording.ids.firstIndex(of: culprit),
              let start = recording.frames.first else { return nil }
        let p = start[idx].position.cgPoint
        let s = cameraNode.xScale
        return CGPoint(x: (p.x - cameraNode.position.x) / s + size.width / 2,
                       y: size.height / 2 - (p.y - cameraNode.position.y) / s)
    }

    public var blamedPiece: Piece? { recording.culprit.flatMap { level.piece($0) } }
}
