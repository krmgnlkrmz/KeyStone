import BalanceCore
import CoreGraphics
import Foundation
import SpriteKit
#if os(iOS)
import UIKit
#endif

/// Why a tapped piece can't be removed (the app turns this into a short toast).
public enum LockedReason: Sendable, Equatable {
    case fixed, keystone, support, notRemovable
}

/// Localised text the scene draws itself (support ghost tags).
public struct SceneStrings: Sendable {
    public var fitsHere: String
    public var wontFit: String
    public var supportHere: String
    public init(fitsHere: String, wontFit: String, supportHere: String) {
        self.fitsHere = fitsHere; self.wontFit = wontFit; self.supportHere = supportHere
    }
    public static let english = SceneStrings(fitsHere: "Fits here", wontFit: "Won't fit", supportHere: "Support here")
}

@MainActor
public protocol GameSceneDelegate: AnyObject {
    func gameSceneDidBecomeReady(_ scene: GameScene)
    func gameScene(_ scene: GameScene, didSelect pieceId: String?)
    func gameScene(_ scene: GameScene, requestsRemovalOf pieceId: String)
    func gameScene(_ scene: GameScene, tappedLocked pieceId: String, reason: LockedReason)
    func gameScene(_ scene: GameScene, didFinish result: EvaluationResult)
    /// Camera or layout changed; overlays that track pieces should refresh.
    func gameSceneLayoutDidChange(_ scene: GameScene)
}

/// The interactive play area: skins, camera, touches, overlays on top of `SimulationScene`.
///
/// Input model (§6.3): the first tap selects (amber outline + lift), a second tap on the selected
/// piece removes it. There is deliberately no single-tap mode.
@MainActor
public final class GameScene: SimulationScene, SimulationSceneDelegate {
    public weak var gameDelegate: GameSceneDelegate?
    public var palette: ScenePalette { didSet { if palette.isDark != oldValue.isDark { reskin() } } }
    public var reduceMotion: Bool
    public var strings: SceneStrings = .english
    /// The app locks input while sheets, hints or the solution demo are up.
    public var inputEnabled = true
    public private(set) var selectedId: String?
    /// Tutorial target (dashed breathing halo).
    public var tapTargetId: String? { didSet { refreshStates() } }

    public let cameraNode = SKCameraNode()
    private let ghostLayer = SKNode()
    private let fxLayer = SKNode()
    private let ropeLayer = SKNode()
    private let groundLayer = SKNode()
    private var ropeShapes: [String: SKShapeNode] = [:]
    private var tiers: [String: TensionTier] = [:]
    private var hintToken: String?
    private var supportGhost: SKNode?

    /// Magnification over the fit framing, 1…2.5.
    public private(set) var zoom: CGFloat = 1
    private var fitScale: CGFloat = 1
    private var focus: CGPoint = .zero

    private var touchStart: CGPoint?
    private var touchPiece: String?
    private var lastEmptyTap: TimeInterval?

    public init(level: Level, size: CGSize, palette: ScenePalette, reduceMotion: Bool) {
        self.palette = palette
        self.reduceMotion = reduceMotion
        super.init(level: level, size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        simulationDelegate = self
        addChild(cameraNode)
        camera = cameraNode
        groundLayer.zPosition = -10
        ghostLayer.zPosition = -1
        ropeLayer.zPosition = 1
        fxLayer.zPosition = 20
        world.zPosition = 0
        addChild(groundLayer)
        addChild(ghostLayer)
        addChild(ropeLayer)
        addChild(fxLayer)
        focus = level.bounds.center.cgPoint
        buildGround()
    }

    // MARK: Lifecycle

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.ignoresSiblingOrder = true
        #if os(iOS)
        view.isMultipleTouchEnabled = true
        if view.gestureRecognizers?.contains(where: { $0 is UIPinchGestureRecognizer }) != true {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = true
            view.addGestureRecognizer(pinch)
        }
        #endif
        frameCamera(animated: false)
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        frameCamera(animated: false)
    }

    public override func didBuild(_ structure: BuiltStructure) {
        selectedId = nil
        ghostLayer.removeAllChildren()
        ropeLayer.removeAllChildren()
        ropeShapes.removeAll()
        fxLayer.removeAllChildren()
        supportGhost = nil
        for id in structure.presentIds {
            guard let node = structure.node(id), let piece = structure.piece(id) else { continue }
            PieceSkin.attach(to: node, piece: piece, palette: palette, interactive: true)
            node.zPosition = SupportToken.isSupport(id) ? 1 : (piece.material == .brass ? 3 : 2)
        }
        for id in log.removedIds {
            if let p = level.piece(id) { ghostLayer.addChild(PieceSkin.ghost(piece: p, palette: palette, alpha: 0.6)) }
        }
        for jid in structure.jointOrder where structure.joints[jid]?.spec.type == .rope {
            let shape = SKShapeNode()
            shape.strokeColor = palette.rope
            shape.lineWidth = 3
            shape.lineCap = .round
            ropeLayer.addChild(shape)
            ropeShapes[jid] = shape
        }
        updateRopes()
        refreshStates()
        gameDelegate?.gameSceneLayoutDidChange(self)
    }

    private func reskin() {
        PieceTextureFactory.shared.flush()
        groundLayer.removeAllChildren()
        buildGround()
        if let structure { didBuild(structure) }
    }

    public override func pieceWillBeRemoved(_ id: String, node: SKNode?) {
        if selectedId == id { selectedId = nil }
        if let shape = ropeShapes.removeValue(forKey: id) { shape.removeFromParent() }
        guard let node, let piece = structure?.piece(id),
              let sprite = node.childNode(withName: PieceSkin.skinName) as? SKSpriteNode else { return }
        // Lift-and-fade copy of the piece; the physics body leaves immediately.
        let copy = SKSpriteNode(texture: sprite.texture, size: sprite.size)
        copy.position = node.convert(sprite.position, to: self)
        copy.zRotation = node.zRotation
        fxLayer.addChild(copy)
        let fade = SKAction.fadeOut(withDuration: 0.26)
        let animation: SKAction = reduceMotion ? fade
            : .group([fade, .moveBy(x: 0, y: 12, duration: 0.26), .scale(to: 0.9, duration: 0.26)])
        animation.timingMode = .easeOut
        copy.run(.sequence([animation, .removeFromParent()]))
        var ghostPiece = piece
        if let pose = structure?.pose(id) { ghostPiece.position = pose.position; ghostPiece.rotation = pose.rotation }
        let ghost = PieceSkin.ghost(piece: ghostPiece, palette: palette, alpha: 0)
        ghostLayer.addChild(ghost)
        ghost.run(.sequence([.wait(forDuration: 0.2), .fadeAlpha(to: 0.6, duration: 0.25)]))
    }

    public override func supportWasPlaced(_ placement: SupportPlacement, node: SKNode) {
        hideSupportGhost()
        if let piece = structure?.piece(placement.token) {
            PieceSkin.attach(to: node, piece: piece, palette: palette, interactive: true)
            node.zPosition = 1
        }
    }

    public override func phaseDidChange(_ phase: SimulationPhase) {
        if phase != .ready { select(nil, notify: false) }
    }

    public override func didFinishUpdate() {
        updateRopes()
    }

    private func updateRopes() {
        guard let structure else { return }
        for (jid, shape) in ropeShapes {
            guard let (a, b) = structure.ropeEndpoints(jid) else { shape.path = nil; continue }
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            shape.path = path
        }
    }

    // MARK: SimulationSceneDelegate

    public func simulationSceneDidBecomeReady(_ scene: SimulationScene) {
        gameDelegate?.gameSceneDidBecomeReady(self)
    }

    public func simulationScene(_ scene: SimulationScene, didFinish result: EvaluationResult) {
        if result.verdict.outcome == .collapsed { shake() }
        gameDelegate?.gameScene(self, didFinish: result)
    }

    // MARK: Ground

    private func buildGround() {
        let y = CGFloat(level.resolvedFloorY)
        let b = level.bounds
        let shadowW = CGFloat(b.width) + 120
        let shadow = SKSpriteNode(texture: Self.radialTexture(), size: CGSize(width: shadowW, height: 60))
        shadow.position = CGPoint(x: CGFloat(b.center.x), y: y + 8)
        shadow.alpha = palette.isDark ? 0.9 : 0.5
        groundLayer.addChild(shadow)
        let line = SKSpriteNode(color: palette.ground, size: CGSize(width: 4000, height: 1.5))
        line.position = CGPoint(x: 0, y: y - 0.75)
        groundLayer.addChild(line)
        let hatch = SKShapeNode()
        let path = CGMutablePath()
        var x: CGFloat = -800
        while x < 800 {
            path.move(to: CGPoint(x: x, y: y - 1.5))
            path.addLine(to: CGPoint(x: x - 12, y: y - 14))
            x += 7
        }
        hatch.path = path
        hatch.strokeColor = palette.ground.withAlphaComponent(0.6)
        hatch.lineWidth = 1
        groundLayer.addChild(hatch)
    }

    private static var radialCache: SKTexture?
    private static func radialTexture() -> SKTexture {
        if let t = radialCache { return t }
        let size = 64
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: cs, colors: [SKColor(white: 0, alpha: 0.22).cgColor, SKColor(white: 0, alpha: 0).cgColor] as CFArray,
                           locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        let t = SKTexture(cgImage: ctx.makeImage()!)
        radialCache = t
        return t
    }

    // MARK: Camera

    /// The play area always shows at least the 300 × 380 design box, so piece sizes stay consistent.
    public var framingBounds: CGRect {
        let b = level.bounds
        var r = CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height)
        let minW: CGFloat = 300, minH: CGFloat = 380
        if r.width < minW { r = r.insetBy(dx: -(minW - r.width) / 2, dy: 0) }
        if r.height < minH { r.size.height = minH } // grow upwards from the floor
        return r.insetBy(dx: -14, dy: -18)
    }

    public func frameCamera(animated: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let r = framingBounds
        fitScale = max(r.width / size.width, r.height / size.height)
        focus = clampFocus(focus)
        applyCamera(animated: animated)
    }

    private func applyCamera(animated: Bool) {
        let scale = fitScale / zoom
        let pos = zoom <= 1.001 ? CGPoint(x: framingBounds.midX, y: framingBounds.midY) : focus
        if animated && !reduceMotion {
            cameraNode.run(.group([.scale(to: scale, duration: 0.25), .move(to: pos, duration: 0.25)]))
        } else {
            cameraNode.setScale(scale)
            cameraNode.position = pos
        }
        gameDelegate?.gameSceneLayoutDidChange(self)
    }

    private func clampFocus(_ p: CGPoint) -> CGPoint {
        let r = framingBounds
        return CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    public func setZoom(_ z: CGFloat, focus f: CGPoint? = nil, animated: Bool) {
        zoom = min(max(z, 1), 2.5)
        if let f { focus = clampFocus(f) }
        applyCamera(animated: animated)
    }

    /// Double-tap: fit ↔ 2×.
    public func toggleZoom(at scenePoint: CGPoint) {
        if zoom > 1.01 { setZoom(1, animated: true) } else { setZoom(2, focus: scenePoint, animated: true) }
    }

    #if os(iOS)
    private var pinchStartZoom: CGFloat = 1
    private var pinchStartFocus: CGPoint = .zero
    private var pinchStartLocation: CGPoint = .zero

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let view = g.view else { return }
        let loc = g.location(in: view)
        switch g.state {
        case .began:
            pinchStartZoom = zoom
            pinchStartFocus = zoom > 1.001 ? focus : CGPoint(x: framingBounds.midX, y: framingBounds.midY)
            pinchStartLocation = loc
            select(nil, notify: true)
        case .changed:
            let newZoom = min(max(pinchStartZoom * g.scale, 1), 2.5)
            let s = fitScale / newZoom
            let dx = (loc.x - pinchStartLocation.x) * s, dy = (loc.y - pinchStartLocation.y) * s
            zoom = newZoom
            focus = clampFocus(CGPoint(x: pinchStartFocus.x - dx, y: pinchStartFocus.y + dy))
            applyCamera(animated: false)
        default:
            break
        }
    }
    #endif

    /// Shake on collapse (6 pt, 0.3 s). Off under Reduce Motion.
    public func shake() {
        guard !reduceMotion else { return }
        let base = cameraNode.position
        var actions: [SKAction] = []
        for i in 0..<6 {
            let a = 6 * (1 - CGFloat(i) / 6) * cameraNode.xScale
            actions.append(.move(to: CGPoint(x: base.x + sin(CGFloat(i) * 2.7) * a, y: base.y + cos(CGFloat(i) * 3.1) * a * 0.6), duration: 0.05))
        }
        actions.append(.move(to: base, duration: 0.05))
        cameraNode.run(.sequence(actions), withKey: "shake")
    }

    // MARK: Coordinates

    /// Scene point → point in the hosting view (y down). Valid for `.resizeFill`.
    public func viewPoint(fromScene p: CGPoint) -> CGPoint {
        let s = cameraNode.xScale
        return CGPoint(x: (p.x - cameraNode.position.x) / s + size.width / 2,
                       y: size.height / 2 - (p.y - cameraNode.position.y) / s)
    }

    public func scenePoint(fromView v: CGPoint) -> CGPoint {
        let s = cameraNode.xScale
        return CGPoint(x: (v.x - size.width / 2) * s + cameraNode.position.x,
                       y: (size.height / 2 - v.y) * s + cameraNode.position.y)
    }

    /// Frame of a piece in view coordinates (for accessibility elements and callouts).
    public func viewFrame(of id: String) -> CGRect? {
        guard let structure, let node = structure.node(id), let piece = structure.piece(id) else { return nil }
        let b = PieceTextureFactory.localBounds(piece)
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
            .map { viewPoint(fromScene: node.convert($0, to: self)) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    public var structureViewFrame: CGRect {
        let r = framingBounds
        let a = viewPoint(fromScene: CGPoint(x: r.minX, y: r.maxY)), b = viewPoint(fromScene: CGPoint(x: r.maxX, y: r.minY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    // MARK: Hit testing

    /// The piece (or rope) under a scene point, with a 44 pt minimum target. Exact hits win over padded ones.
    public func hitPiece(at p: CGPoint) -> String? {
        guard let structure else { return nil }
        let pad = PieceSkin.minimumHitSize * cameraNode.xScale
        var best: (id: String, exact: Bool, distance: CGFloat, z: CGFloat)?
        for id in structure.presentIds.reversed() {
            guard let node = structure.node(id), let piece = structure.piece(id) else { continue }
            let local = node.convert(p, from: self)
            let b = PieceTextureFactory.localBounds(piece)
            let padded = b.insetBy(dx: -max(0, (pad - b.width) / 2), dy: -max(0, (pad - b.height) / 2))
            guard padded.contains(local) else { continue }
            let exact = b.contains(local)
            let d = hypot(local.x - b.midX, local.y - b.midY) / max(1, min(b.width, b.height))
            let candidate = (id, exact, d, node.zPosition)
            if let cur = best {
                if (exact && !cur.exact) || (exact == cur.exact && (candidate.3 > cur.z || (candidate.3 == cur.z && d < cur.distance))) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        if let best { return best.id }
        // Ropes: distance to the segment.
        for (jid, _) in ropeShapes {
            guard let (a, b) = structure.ropeEndpoints(jid) else { continue }
            if distance(from: p, toSegment: a, b) < pad / 2 { return jid }
        }
        return nil
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    public func lockedReason(_ id: String) -> LockedReason {
        if SupportToken.isSupport(id) { return .support }
        guard let p = structure?.piece(id) else { return .notRemovable }
        if p.fixed { return .fixed }
        if p.material == .brass { return .keystone }
        return .notRemovable
    }

    // MARK: Touches

    #if os(iOS)
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let t = touches.first, (event?.allTouches?.count ?? 1) == 1 else { return }
        let p = t.location(in: self)
        touchStart = p
        touchPiece = nil
        guard inputEnabled, phase == .ready, let id = hitPiece(at: p) else { return }
        touchPiece = id
        if isRemovable(id), id != selectedId {
            select(id, notify: true) // touch-down feedback
            touchPiece = nil // this touch only selects
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = touchStart else { return }
        let p = t.location(in: self)
        defer { touchStart = nil; touchPiece = nil }
        guard hypot(p.x - start.x, p.y - start.y) < 14 * cameraNode.xScale else { return }
        handleTapEnd(at: p, pieceAtStart: touchPiece, timestamp: t.timestamp)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
        touchPiece = nil
    }
    #endif

    /// Tap logic, separated from UIKit so tests and VoiceOver actions can drive it.
    public func handleTapEnd(at p: CGPoint, pieceAtStart: String?, timestamp: TimeInterval) {
        guard inputEnabled, phase == .ready else { return }
        if let id = pieceAtStart {
            if !isRemovable(id) {
                gameDelegate?.gameScene(self, tappedLocked: id, reason: lockedReason(id))
            } else if id == selectedId, hitPiece(at: p) == id {
                gameDelegate?.gameScene(self, requestsRemovalOf: id)
            }
            lastEmptyTap = nil
            return
        }
        if hitPiece(at: p) == nil {
            if let last = lastEmptyTap, timestamp - last < 0.3 {
                lastEmptyTap = nil
                toggleZoom(at: p)
            } else {
                lastEmptyTap = timestamp
                if selectedId != nil { select(nil, notify: true) }
            }
        }
    }

    /// Accessibility / tests: same two-step model without touches.
    public func activate(_ id: String) {
        guard inputEnabled, phase == .ready else { return }
        if !isRemovable(id) {
            gameDelegate?.gameScene(self, tappedLocked: id, reason: lockedReason(id))
        } else if id == selectedId {
            gameDelegate?.gameScene(self, requestsRemovalOf: id)
        } else {
            select(id, notify: true)
        }
    }

    public func select(_ id: String?, notify: Bool) {
        guard selectedId != id else { return }
        selectedId = id
        refreshStates()
        if notify { gameDelegate?.gameScene(self, didSelect: id) }
    }

    // MARK: Overlays

    public func setTiers(_ newTiers: [String: TensionTier]) {
        tiers = newTiers
        guard let structure else { return }
        for id in structure.presentIds {
            guard let node = structure.node(id), let piece = structure.piece(id) else { continue }
            PieceSkin.setTension(tiers[id] ?? .none, on: node, piece: piece, palette: palette, reduceMotion: reduceMotion)
        }
    }

    /// Rings the hinted move: a piece, a rope, or a support position (ghost strut).
    public func showHint(_ token: String?) {
        hintToken = token
        fxLayer.childNode(withName: "hintSupport")?.removeFromParent()
        if let token, let parsed = SupportToken.parse(token) {
            let placement = SupportGeometry.placement(atX: parsed.x, level: level, removed: log.removedIds, supports: placedSupports)
            let ghost = supportGhostNode(placement, valid: true, label: strings.supportHere)
            ghost.name = "hintSupport"
            fxLayer.addChild(ghost)
        }
        refreshStates()
    }

    private func refreshStates() {
        guard let structure else { return }
        for id in structure.presentIds {
            guard let node = structure.node(id), let piece = structure.piece(id) else { continue }
            let state: PieceVisualState
            if id == hintToken { state = .hint }
            else if id == selectedId { state = .selected }
            else if id == tapTargetId && log.isEmpty { state = .tapTarget }
            else { state = .normal }
            PieceSkin.setState(state, on: node, piece: piece, palette: palette, reduceMotion: reduceMotion)
        }
        for (jid, shape) in ropeShapes {
            shape.strokeColor = jid == selectedId || jid == hintToken ? palette.accent : palette.rope
            shape.lineWidth = jid == selectedId ? 4 : 3
        }
    }

    // MARK: Support drag

    /// Shows the ghost strut under a view point and returns the placement it would make.
    @discardableResult
    public func showSupportGhost(atViewPoint v: CGPoint) -> SupportPlacement? {
        let p = scenePoint(fromView: v)
        let r = framingBounds.insetBy(dx: -40, dy: -60)
        guard r.contains(p) else { hideSupportGhost(); return nil }
        let placement = supportPreview(atX: Double(p.x))
        supportGhost?.removeFromParent()
        let node = supportGhostNode(placement, valid: placement.isValid, label: placement.isValid ? strings.fitsHere : strings.wontFit)
        fxLayer.addChild(node)
        supportGhost = node
        return placement
    }

    public func hideSupportGhost() {
        supportGhost?.removeFromParent()
        supportGhost = nil
    }

    private func supportGhostNode(_ p: SupportPlacement, valid: Bool, label: String) -> SKNode {
        let holder = SKNode()
        let rect = CGRect(x: p.x - p.width / 2, y: p.bottomY, width: p.width, height: max(20, p.height))
        let body = SKShapeNode(path: CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil).copy(dashingWithPhase: 0, lengths: [4, 3]))
        body.strokeColor = valid ? palette.jade : palette.text3
        body.fillColor = valid ? palette.jadeSoft : palette.line2.withAlphaComponent(0.25)
        body.lineWidth = 1.5
        holder.addChild(body)
        if valid {
            let frame = SKShapeNode(rect: rect.insetBy(dx: -5, dy: -5), cornerRadius: 6)
            frame.strokeColor = palette.jade
            frame.lineWidth = 1.5
            holder.addChild(frame)
        }
        let tag = SKLabelNode(text: label)
        tag.fontName = "HelveticaNeue-Medium"
        tag.fontSize = 13
        tag.fontColor = palette.text
        tag.horizontalAlignmentMode = .left
        tag.verticalAlignmentMode = .center
        let tagBox = SKShapeNode(rect: CGRect(x: -10, y: -14, width: tag.frame.width + 20, height: 28), cornerRadius: 10)
        tagBox.fillColor = palette.surface
        tagBox.strokeColor = valid ? palette.jade : palette.line2
        tagBox.lineWidth = 1.5
        tagBox.addChild(tag)
        tagBox.position = CGPoint(x: p.x + 22, y: p.bottomY + max(20, p.height) / 2)
        tagBox.zPosition = 2
        tagBox.setScale(cameraNode.xScale)
        holder.addChild(tagBox)
        return holder
    }

    // MARK: Success art

    /// Draws dimension lines around the standing structure (Level Clear).
    public func showDimensions(widthLabel: String, heightLabel: String) {
        fxLayer.childNode(withName: "dims")?.removeFromParent()
        guard let all = standingBounds else { return }
        let floor = CGFloat(level.resolvedFloorY)
        let holder = SKNode()
        holder.name = "dims"
        func dim(_ a: CGPoint, _ b: CGPoint, _ text: String, vertical: Bool) {
            let path = CGMutablePath()
            path.move(to: a); path.addLine(to: b)
            for end in [a, b] {
                if vertical { path.move(to: CGPoint(x: end.x - 5, y: end.y)); path.addLine(to: CGPoint(x: end.x + 5, y: end.y)) }
                else { path.move(to: CGPoint(x: end.x, y: end.y - 5)); path.addLine(to: CGPoint(x: end.x, y: end.y + 5)) }
            }
            let line = SKShapeNode(path: path)
            line.strokeColor = palette.accent
            line.lineWidth = 1
            line.alpha = 0
            holder.addChild(line)
            let label = SKLabelNode(text: text)
            label.fontName = "Menlo"
            label.fontSize = 10
            label.fontColor = palette.accent
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = vertical ? .left : .center
            label.position = vertical ? CGPoint(x: a.x + 8, y: (a.y + b.y) / 2) : CGPoint(x: (a.x + b.x) / 2, y: a.y + 9)
            label.alpha = 0
            holder.addChild(label)
            let fade = SKAction.fadeIn(withDuration: reduceMotion ? 0.01 : 0.35)
            line.run(fade)
            label.run(.sequence([.wait(forDuration: reduceMotion ? 0 : 0.2), fade]))
        }
        dim(CGPoint(x: all.minX, y: all.maxY + 26), CGPoint(x: all.maxX, y: all.maxY + 26), widthLabel, vertical: false)
        dim(CGPoint(x: all.maxX + 20, y: all.maxY), CGPoint(x: all.maxX + 20, y: floor), heightLabel, vertical: true)
        fxLayer.addChild(holder)
    }

    /// Design-space size of what is standing, in metres (100 pt = 1 m in the design kit).
    public var standingExtent: (width: Double, height: Double) {
        guard let all = standingBounds else { return (0, 0) }
        return (Double(all.width) / 100, Double(all.maxY - CGFloat(level.resolvedFloorY)) / 100)
    }

    /// Bounds of the pieces at their current poses (outlines only, no touch padding or overlays).
    public var standingBounds: CGRect? {
        guard let structure else { return nil }
        var pts: [Vec2] = []
        for id in structure.presentIds {
            guard let piece = structure.piece(id), let pose = structure.pose(id) else { continue }
            pts += piece.shape.localOutline.map { $0.rotated(by: pose.rotation) + pose.position }
        }
        guard !pts.isEmpty else { return nil }
        let r = Rect2.enclosing(pts)
        return CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }
}
