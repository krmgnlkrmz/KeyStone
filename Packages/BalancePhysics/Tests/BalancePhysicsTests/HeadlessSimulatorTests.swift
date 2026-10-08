import BalanceCore
@testable import BalancePhysics
import Foundation
import Metal
import Testing

/// Two posts, a beam, a block on top. Removing a post must collapse it; removing the block must not.
func table(floor: Double = -100) -> Level {
    Level(id: "t-table", pack: .curated, region: Region.woodScaffold.rawValue, index: 1, floorY: floor,
          goal: Goal(type: .removeTargetsKeepStanding, targetPieceIds: ["load"], moveBudget: 3, starThresholds: [1, 2, 3]),
          pieces: [
            Piece(id: "l", material: .wood, shape: .rect(w: 20, h: 80), position: Vec2(-80, floor + 40)),
            Piece(id: "r", material: .wood, shape: .rect(w: 20, h: 80), position: Vec2(80, floor + 40)),
            Piece(id: "beam", material: .wood, shape: .rect(w: 200, h: 18), position: Vec2(0, floor + 89)),
            Piece(id: "load", material: .stone, shape: .rect(w: 40, h: 40), position: Vec2(0, floor + 118)),
          ])
}

let hasMetal = MTLCreateSystemDefaultDevice() != nil

@MainActor
@Suite("Headless simulator", .enabled(if: hasMetal, "needs a Metal device for SKRenderer"))
struct HeadlessSimulatorTests {
    @Test func rendererStepsPhysics() throws {
        let sim = try HeadlessSimulator()
        try sim.selfTest()
    }

    @Test func untouchedTableStands() throws {
        let sim = try HeadlessSimulator()
        let r = try sim.run(.init(level: table(), move: nil))
        #expect(r.verdict.outcome == .standing, "worst \(r.verdict.worstRatio) on \(r.verdict.worstBodyId ?? "-")")
        #expect(r.verdict.worstRatio < 0.3)
    }

    @Test func removingALegCollapses() throws {
        let sim = try HeadlessSimulator()
        let r = try sim.run(.init(level: table(), move: .remove(pieceId: "l")))
        #expect(r.verdict.outcome == .collapsed)
        #expect(r.moveResult == .collapsed)
        #expect(r.collapseTime != nil)
        #expect(r.heuristicCulprit != nil)
    }

    @Test func removingTheLoadWins() throws {
        let sim = try HeadlessSimulator()
        let r = try sim.run(.init(level: table(), move: .remove(pieceId: "load")))
        #expect(r.verdict.outcome == .standing)
        #expect(r.moveResult == .won)
    }

    /// Re-simulating a job reaches the same decision, whatever ran before and on a fresh simulator.
    /// Recordings are not promised bit-identical across simulator instances: SpriteKit orders bodies
    /// internally, and an exactly symmetric structure may settle a hair to either side. Poses are
    /// therefore compared with a tolerance at the start of the window, decisions exactly.
    @Test func sameJobSameDecision() throws {
        let sim = try HeadlessSimulator()
        let job = HeadlessSimulator.Job(level: table(), move: .remove(pieceId: "r"))
        let a = try sim.run(job)
        _ = try sim.run(.init(level: table(floor: -140), move: .remove(pieceId: "load"), profile: .jitter))
        let b = try sim.run(job)
        let c = try HeadlessSimulator().run(job)
        for other in [b, c] {
            #expect(other.verdict.outcome == a.verdict.outcome)
            #expect(other.moveResult == a.moveResult)
            #expect(other.heuristicCulprit == a.heuristicCulprit)
            let start = other.recording.poses(at: 0)
            for (id, p) in a.recording.poses(at: 0) {
                let q = try #require(start[id])
                #expect(p.translation(from: q) < 0.5, "\(id) settled \(p.translation(from: q)) pt apart")
                #expect(p.rotationDelta(from: q) < 0.01, "\(id) settled \(p.rotationDelta(from: q)) rad apart")
            }
        }
    }

    @Test func undoReplayMatchesForwardPlay() throws {
        // Forward: remove load, (settle), then evaluate nothing. Replay: rebuild with load removed.
        let sim = try HeadlessSimulator()
        var base = MoveLog()
        base.append(.remove(pieceId: "load"))
        let forward = try sim.run(.init(level: table(), move: .remove(pieceId: "load")))
        let replayed = try sim.run(.init(level: table(), base: base, move: nil))
        for id in ["l", "r", "beam"] {
            let f = forward.recording.poses(at: forward.duration)[id]!
            let u = replayed.recording.poses(at: replayed.duration)[id]!
            #expect(f.translation(from: u) < 1.0, "\(id) drifted \(f.translation(from: u))")
            #expect(f.rotationDelta(from: u) < 0.01)
        }
    }
}
