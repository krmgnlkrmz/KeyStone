import BalanceCore
import CoreGraphics
import SpriteKit

/// Outcome of one evaluation window (after a move, or of an untouched state).
public struct EvaluationResult: Sendable {
    public var move: Move.Kind?
    /// State key before the move.
    public var stateKeyBefore: String
    /// State key after the move.
    public var stateKeyAfter: String
    public var verdict: SettleVerdict
    public var metrics: [BodyMetrics]
    /// Game-level reading of the verdict (won / collapsed / continue / out of moves).
    public var moveResult: MoveResult
    /// Physics time (since the move) when the first watched body crossed its tolerance.
    public var collapseTime: Double?
    /// Physics time the window ran for.
    public var duration: Double
    public var recording: Recording
    /// Runtime blame (§4.4 step 2). The game prefers the offline annotation when it has one.
    public var heuristicCulprit: String?
}

public enum SimulationPhase: Equatable, Sendable {
    case empty
    /// Quiet settle after (re)building. Input locked, nothing evaluated.
    case presettling
    /// Waiting for a move.
    case ready
    /// A move is being evaluated (input locked, screen alive).
    case evaluating
    /// Won, collapsed or out of moves. Physics keeps running for the visuals.
    case finished
}

@MainActor
public protocol SimulationSceneDelegate: AnyObject {
    func simulationSceneDidBecomeReady(_ scene: SimulationScene)
    func simulationScene(_ scene: SimulationScene, didFinish result: EvaluationResult)
}

/// The physics half of the game, shared verbatim by the interactive `GameScene` and the headless
/// simulator used by LevelForge: same builder, same constants, same body order, same decision code.
///
/// Time is accounted in physics time: every simulated frame adds its step to the window clock, and
/// the logic only runs after SpriteKit has simulated (`didSimulatePhysics`). A dropped frame makes a
/// single sample cover more physics time; it never shortens the window.
@MainActor
open class SimulationScene: SKScene {
    public let level: Level
    /// Parent of every physics node. Stays at the origin with identity transform.
    public let world = SKNode()
    public private(set) var structure: BuiltStructure?
    public private(set) var log = MoveLog()
    public private(set) var phase: SimulationPhase = .empty
    public weak var simulationDelegate: SimulationSceneDelegate?

    /// How long recording continues after a collapse is detected (the replay tail).
    public var collapseTail: Double = PhysicsConstants.collapseTail
    /// Quiet settle after a (re)build.
    public var presettleDuration: Double = PhysicsConstants.initialSettle

    public let recorder = ReplayRecorder()
    public private(set) var evaluator: SettleEvaluator?
    public private(set) var lastResult: EvaluationResult?

    private var phaseTime: Double = 0
    private var lastUpdateTime: TimeInterval?
    private var frameDT: Double = PhysicsConstants.stepDuration
    private var evaluatingMove: Move.Kind?
    private var stateKeyBefore = ""
    private var removedOrigins: [String: Pose] = [:]

    /// Supports placed so far, resolved against the state at the time of each placement.
    public private(set) var placedSupports: [SupportPlacement] = []

    public init(level: Level, size: CGSize) {
        self.level = level
        super.init(size: size)
        physicsWorld.gravity = PhysicsConstants.gravityVector
        physicsWorld.speed = 1.0
        world.name = "world"
        addChild(world)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Building

    /// Rebuilds from scratch with `log` applied — no windows between moves — then settles quietly.
    /// Undo is `load(log: log.truncated(to: n - 1))`: the state after undo is, by definition, the
    /// state of replaying the remaining moves.
    open func load(log newLog: MoveLog) {
        physicsWorld.removeAllJoints()
        world.removeAllChildren()
        log = newLog
        evaluator = nil
        evaluatingMove = nil
        lastResult = nil

        var removed = Set<String>()
        var supports: [SupportPlacement] = []
        for move in newLog.moves {
            switch move.kind {
            case let .remove(id):
                removed.insert(id)
            case let .placeSupport(pos, _):
                let p = SupportGeometry.placement(atX: pos.x, level: level, removed: removed, supports: supports)
                if p.isValid { supports.append(p) }
            }
        }
        placedSupports = supports
        let built = StructureSceneBuilder.build(level: level, removed: removed, supports: supports,
                                                parent: world, physicsWorld: physicsWorld)
        structure = built
        didBuild(built)
        phase = .presettling
        phaseTime = 0
    }

    /// Hook for visuals (skins, ropes, ghosts). Called after every (re)build.
    open func didBuild(_ structure: BuiltStructure) {}
    /// Hook called just before a piece's node leaves the scene.
    open func pieceWillBeRemoved(_ id: String, node: SKNode?) {}
    /// Hook called after a support node joined the scene.
    open func supportWasPlaced(_ placement: SupportPlacement, node: SKNode) {}
    /// Hook called when the phase changes.
    open func phaseDidChange(_ phase: SimulationPhase) {}

    // MARK: Moves

    public var dropTargets: Set<String> {
        level.goal.type == .dropOnlyTarget ? Set(level.goal.targetPieceIds) : []
    }

    public func isRemovable(_ id: String) -> Bool {
        guard let structure else { return false }
        if structure.joints[id] != nil { return structure.joints[id]!.spec.isRemovable }
        return structure.piece(id)?.removable == true && structure.node(id) != nil
    }

    /// Supports still available to place.
    public var supportsLeft: Int { max(0, level.supportsAllowed - log.supportsPlaced) }

    /// Strut geometry for a drag at `x` (snapped to the solver's candidate positions when close).
    public func supportPreview(atX x: Double) -> SupportPlacement {
        let candidates = SupportGeometry.candidates(level: level, removed: log.removedIds, supports: placedSupports)
        if let snapped = SupportGeometry.snapToCandidate(x: x, candidates: candidates) { return snapped }
        var p = SupportGeometry.placement(atX: x, level: level, removed: log.removedIds, supports: placedSupports)
        p.isValid = false
        return p
    }

    /// Applies a move and opens an evaluation window. Returns false when the move is not allowed now.
    @discardableResult
    open func apply(_ kind: Move.Kind) -> Bool {
        guard phase == .ready, let structure else { return false }
        if log.count >= level.goal.moveBudget { return false }
        var origins: [String: Pose] = [:]
        switch kind {
        case let .remove(id):
            guard isRemovable(id) else { return false }
            if let pose = structure.pose(id) { origins[id] = pose }
            pieceWillBeRemoved(id, node: structure.node(id))
            structure.remove(id)
        case let .placeSupport(pos, _):
            guard supportsLeft > 0 else { return false }
            let candidates = SupportGeometry.candidates(level: level, removed: log.removedIds, supports: placedSupports)
            guard let placement = candidates.first(where: { abs($0.x - pos.x) < 0.5 }) else { return false }
            let node = StructureSceneBuilder.addSupport(placement, to: structure, parent: world)
            placedSupports.append(placement)
            supportWasPlaced(placement, node: node)
        }
        stateKeyBefore = log.stateKey
        log.append(kind)
        startWindow(move: kind, removedOrigins: origins)
        return true
    }

    /// Opens an evaluation window without a move (is this state stable on its own?).
    public func evaluateWithoutMove() {
        guard phase == .ready || phase == .presettling else { return }
        stateKeyBefore = log.stateKey
        startWindow(move: nil, removedOrigins: [:])
    }

    private func startWindow(move: Move.Kind?, removedOrigins origins: [String: Pose]) {
        guard let structure else { return }
        evaluatingMove = move
        removedOrigins = origins
        evaluator = SettleEvaluator(structure: structure, dropTargets: dropTargets)
        let supports = structure.presentIds.filter(SupportToken.isSupport).compactMap { structure.piece($0) }
        recorder.begin(ids: structure.presentIds, removedOrigins: origins, extraPieces: supports)
        recorder.record(time: 0, structure: structure)
        setPhase(.evaluating)
        phaseTime = 0
    }

    private func setPhase(_ p: SimulationPhase) {
        phase = p
        phaseDidChange(p)
    }

    // MARK: Frame loop

    open override func update(_ currentTime: TimeInterval) {
        if let last = lastUpdateTime {
            frameDT = min(max(currentTime - last, 0), 1.0 / 20.0)
        } else {
            frameDT = PhysicsConstants.stepDuration
        }
        lastUpdateTime = currentTime
    }

    /// Resets the frame clock (after a pause) so the next frame does not count the paused time.
    public func resetFrameClock() { lastUpdateTime = nil }

    open override func didSimulatePhysics() {
        tick(dt: frameDT)
    }

    func tick(dt: Double) {
        switch phase {
        case .presettling:
            phaseTime += dt
            if phaseTime >= presettleDuration - 1e-9 {
                setPhase(.ready)
                simulationDelegate?.simulationSceneDidBecomeReady(self)
            }
        case .evaluating:
            guard let evaluator, let structure else { return }
            phaseTime += dt
            evaluator.sample(time: phaseTime)
            recorder.record(time: phaseTime, structure: structure)
            let eps = 1e-9
            if let c = evaluator.firstCollapseTime {
                if phaseTime - c >= collapseTail - eps || phaseTime >= PhysicsConstants.maxSimSeconds - eps { finishWindow() }
            } else if phaseTime >= PhysicsConstants.settleWindow - eps && evaluator.allResting {
                finishWindow()
            } else if phaseTime >= PhysicsConstants.maxSimSeconds - eps {
                finishWindow()
            }
        default:
            break
        }
    }

    private func finishWindow() {
        guard let evaluator, let structure else { return }
        let verdict = evaluator.verdict()
        let metrics = evaluator.metrics()
        let result = GoalRules.result(goal: level.goal, removed: log.removedIds, supportsPlaced: log.supportsPlaced,
                                      movesMade: log.count, outcome: verdict.outcome)
        var recording = recorder.freeze(levelId: level.id, collapseTime: evaluator.firstCollapseTime,
                                        culprit: nil, moveNumber: log.count)
        var culprit: String?
        if verdict.outcome == .collapsed {
            var bounds: [String: Rect2] = [:]
            for id in structure.presentIds { if let p = structure.piece(id) { bounds[id] = p.worldBounds } }
            culprit = CulpritHeuristic.culprit(frames: recording.keyedFrames,
                                               collapseFrame: recording.firstFrame(atOrAfter: evaluator.firstCollapseTime ?? 0),
                                               bounds: bounds,
                                               candidates: Set(structure.monitoredIds).subtracting(dropTargets))
            recording.culprit = culprit
        }
        let r = EvaluationResult(move: evaluatingMove, stateKeyBefore: stateKeyBefore, stateKeyAfter: log.stateKey,
                                 verdict: verdict, metrics: metrics, moveResult: evaluatingMove == nil ? .continuePlaying : result,
                                 collapseTime: evaluator.firstCollapseTime, duration: phaseTime,
                                 recording: recording, heuristicCulprit: culprit)
        lastResult = r
        self.evaluator = nil
        let next: SimulationPhase
        if evaluatingMove == nil {
            next = verdict.outcome == .standing ? .ready : .finished
        } else {
            next = result == .continuePlaying ? .ready : .finished
        }
        setPhase(next)
        simulationDelegate?.simulationScene(self, didFinish: r)
    }
}
