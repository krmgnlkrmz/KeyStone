import BalanceCore
import CoreGraphics
import Foundation
import Metal
import SpriteKit

/// Frame-timing profile for a headless run. `dts` repeats; each entry is one simulated frame.
public struct StepProfile: Sendable, Hashable, CustomStringConvertible {
    public var name: String
    public var dts: [Double]

    public init(name: String, dts: [Double]) {
        self.name = name
        self.dts = dts
    }

    public var description: String { name }

    /// What the game runs: a steady 60 Hz.
    public static let standard = StepProfile(name: "60hz", dts: [1.0 / 60])
    /// ProMotion panel stepping at 120 Hz.
    public static let promotion = StepProfile(name: "120hz", dts: [1.0 / 120])
    /// A dropped frame every seventh frame.
    public static let dropEvery7 = StepProfile(name: "drop7", dts: Array(repeating: 1.0 / 60, count: 6) + [2.0 / 60])
    /// Display-link jitter around 60 Hz.
    public static let jitter = StepProfile(name: "jitter", dts: [0.0158, 0.0175, 0.0162, 0.0171, 0.0167, 0.0160, 0.0174])
    /// A struggling device at 45 Hz.
    public static let slow = StepProfile(name: "45hz", dts: [1.0 / 45])

    /// The five validation runs (§4.2 rule 4).
    public static let validationSet: [StepProfile] = [.standard, .promotion, .dropEvery7, .jitter, .slow]
}

public enum HeadlessError: Error, CustomStringConvertible {
    case noMetalDevice
    case physicsNotStepping
    case stalled(String)
    case rejectedMove(String)

    public var description: String {
        switch self {
        case .noMetalDevice: return "no Metal device for SKRenderer"
        case .physicsNotStepping: return "SKRenderer.update does not advance physics on this system"
        case let .stalled(s): return "simulation stalled: \(s)"
        case let .rejectedMove(m): return "move rejected: \(m)"
        }
    }
}

/// Runs `SimulationScene` without a view, as fast as the CPU allows, with exact frame times.
///
/// SpriteKit has no public "step the world by dt" call, but `SKRenderer.update(atTime:)` runs one
/// full frame cycle (update → actions → physics → didSimulatePhysics) for the time we pass in. The
/// game scene runs the very same frame cycle from SKView at 60 Hz, so the decision code is shared and
/// only the clock differs. `selfTest()` checks the assumption on the running system.
@MainActor
public final class HeadlessSimulator {
    public struct Job: Sendable {
        public var level: Level
        /// Moves already made (rebuilt from scratch, then a quiet settle).
        public var base: MoveLog
        /// The move to evaluate, or nil to evaluate the base state alone.
        public var move: Move.Kind?
        public var profile: StepProfile
        /// Recording tail after collapse. The solver only needs enough frames to blame a piece.
        public var collapseTail: Double

        public init(level: Level, base: MoveLog = MoveLog(), move: Move.Kind?, profile: StepProfile = .standard,
                    collapseTail: Double = 0.6) {
            self.level = level; self.base = base; self.move = move; self.profile = profile; self.collapseTail = collapseTail
        }
    }

    private let device: any MTLDevice
    private var renderer: SKRenderer
    private var clock: TimeInterval = HeadlessSimulator.clockOrigin
    public private(set) var framesSimulated = 0
    public private(set) var jobsRun = 0

    /// SpriteKit derives each frame's dt from absolute timestamps, so the same dt sequence started at a
    /// different absolute time rounds differently and the physics drifts. Every job therefore starts on a
    /// fresh renderer at the same clock origin: identical jobs see bit-identical frame times.
    private nonisolated static let clockOrigin: TimeInterval = 1000

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw HeadlessError.noMetalDevice }
        self.device = device
        renderer = Self.makeRenderer(device)
    }

    private static func makeRenderer(_ device: any MTLDevice) -> SKRenderer {
        let r = SKRenderer(device: device)
        r.ignoresSiblingOrder = true
        r.shouldCullNonVisibleNodes = false
        return r
    }

    /// Fresh renderer, clock back at its origin.
    private func resetClock() {
        renderer = Self.makeRenderer(device)
        clock = Self.clockOrigin
    }

    /// Drops a box for half a second and checks it fell.
    public func selfTest() throws {
        let probe = Level(id: "probe", pack: .pool, region: Region.woodScaffold.rawValue, index: 0, floorY: -1000,
                          goal: Goal(type: .removeTargetsKeepStanding, targetPieceIds: [], moveBudget: 1, starThresholds: [1, 1, 1]),
                          pieces: [Piece(id: "box", material: .stone, shape: .rect(w: 20, h: 20), position: .zero)])
        let scene = SimulationScene(level: probe, size: CGSize(width: 400, height: 400))
        resetClock()
        renderer.scene = scene
        scene.load(log: MoveLog())
        for _ in 0..<30 { step(scene, dt: 1.0 / 60) }
        guard let y = scene.structure?.pose("box")?.y, y < -10 else { throw HeadlessError.physicsNotStepping }
        renderer.scene = nil
    }

    public func run(_ job: Job) throws -> EvaluationResult {
        let scene = SimulationScene(level: job.level, size: CGSize(width: 600, height: 800))
        scene.collapseTail = job.collapseTail
        resetClock()
        renderer.scene = scene
        defer { renderer.scene = nil; jobsRun += 1 }

        // One warm-up frame so SpriteKit's own clock starts before the structure exists.
        var frame = 0
        step(scene, dt: job.profile.dts[0])
        scene.load(log: job.base)

        let seconds: Double = PhysicsConstants.initialSettle + PhysicsConstants.maxSimSeconds + 2
        let maxFrames = Int(seconds * 240)
        while scene.phase == .presettling {
            step(scene, dt: job.profile.dts[frame % job.profile.dts.count]); frame += 1
            if frame > maxFrames { throw HeadlessError.stalled("presettle \(job.level.id)") }
        }
        guard scene.phase == .ready else { throw HeadlessError.stalled("not ready after presettle") }

        if let move = job.move {
            guard scene.apply(move) else { throw HeadlessError.rejectedMove("\(move.token) in \(job.level.id) @ \(job.base.stateKey)") }
        } else {
            scene.evaluateWithoutMove()
        }
        while scene.phase == .evaluating {
            step(scene, dt: job.profile.dts[frame % job.profile.dts.count]); frame += 1
            if frame > maxFrames { throw HeadlessError.stalled("window \(job.level.id)") }
        }
        guard let result = scene.lastResult else { throw HeadlessError.stalled("no result") }
        return result
    }

    /// Forward play in one scene: each move gets its own evaluation window, exactly like the game
    /// without undo. Returns one result per move (stops early when the level ends).
    public func runSequence(level: Level, moves: [Move.Kind], profile: StepProfile = .standard) throws -> [EvaluationResult] {
        let scene = SimulationScene(level: level, size: CGSize(width: 600, height: 800))
        resetClock()
        renderer.scene = scene
        defer { renderer.scene = nil; jobsRun += 1 }
        var frame = 0
        step(scene, dt: profile.dts[0])
        scene.load(log: MoveLog())
        let windows: Double = PhysicsConstants.maxSimSeconds * Double(max(1, moves.count))
        let seconds: Double = PhysicsConstants.initialSettle + windows + 2
        let maxFrames = Int(seconds * 240)
        while scene.phase == .presettling {
            step(scene, dt: profile.dts[frame % profile.dts.count]); frame += 1
            if frame > maxFrames { throw HeadlessError.stalled("presettle \(level.id)") }
        }
        var results: [EvaluationResult] = []
        for move in moves {
            guard scene.phase == .ready else { break }
            guard scene.apply(move) else { throw HeadlessError.rejectedMove(move.token) }
            while scene.phase == .evaluating {
                step(scene, dt: profile.dts[frame % profile.dts.count]); frame += 1
                if frame > maxFrames { throw HeadlessError.stalled("sequence \(level.id)") }
            }
            if let r = scene.lastResult { results.append(r) }
        }
        return results
    }

    private func step(_ scene: SimulationScene, dt: Double) {
        clock += dt
        renderer.update(atTime: clock)
        framesSimulated += 1
    }
}
