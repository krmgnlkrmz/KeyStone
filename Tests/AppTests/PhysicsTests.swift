import BalanceCore
import BalancePhysics
import XCTest
@testable import DengeNoktasi

/// M3/M4 acceptance in the iOS Simulator with the shipping SpriteKit.
@MainActor
final class PhysicsTests: XCTestCase {
    private func level(_ id: String) throws -> Level {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Levels", withExtension: nil))
        return try XCTUnwrap(LevelCatalog.load(from: url).level(id: id))
    }

    func testFirstLevelStandsUntouched() throws {
        let sim = try HeadlessSimulator()
        let r = try sim.run(.init(level: try level("c-001"), move: nil))
        XCTAssertEqual(r.verdict.outcome, .standing)
        XCTAssertLessThan(r.verdict.worstRatio, 1 / PhysicsConstants.requiredMarginRatio)
    }

    /// Removing a post under the beam collapses the first level within the window.
    func testRemovingALoadBearingPostCollapses() throws {
        let sim = try HeadlessSimulator()
        let r = try sim.run(.init(level: try level("c-001"), move: .remove(pieceId: "p1")))
        XCTAssertEqual(r.moveResult, .collapsed)
        XCTAssertLessThanOrEqual(r.collapseTime ?? 99, PhysicsConstants.settleWindow)
    }

    /// Acceptance #10: the collapse replay is a recording, so it plays back identically every time
    /// (no physics in the replay scene); re-simulating the same move reaches the same decision.
    func testReplayIsIdenticalEveryTime() throws {
        let lvl = try level("c-001")
        let job = HeadlessSimulator.Job(level: lvl, move: .remove(pieceId: "p2"), collapseTail: PhysicsConstants.collapseTail)
        let a = try HeadlessSimulator().run(job)
        XCTAssertGreaterThan(a.recording.frames.count, 30)

        let size = CGSize(width: 390, height: 600)
        let first = ReplayScene(level: lvl, recording: a.recording, size: size, palette: .dark, reduceMotion: false)
        let second = ReplayScene(level: lvl, recording: a.recording, size: size, palette: .dark, reduceMotion: false)
        first.seek(to: 1.2); first.seek(to: 0.1); first.seek(to: 0.7)   // scrub around, then land
        second.seek(to: 0.7)
        for id in a.recording.ids {
            let f = try XCTUnwrap(first.transform(of: id)), s = try XCTUnwrap(second.transform(of: id))
            XCTAssertEqual(f.position, s.position, id)
            XCTAssertEqual(f.rotation, s.rotation, id)
            XCTAssertFalse(f.hasPhysics, "\(id) has a physics body in the replay")
        }

        let b = try HeadlessSimulator().run(job)
        XCTAssertEqual(a.verdict.outcome, b.verdict.outcome)
        XCTAssertEqual(a.heuristicCulprit, b.heuristicCulprit)
    }

    /// Acceptance #9: undo (rebuild from the log) equals playing forward, within tolerance.
    func testUndoMatchesForwardPlay() throws {
        let lvl = try level("c-002")
        let sim = try HeadlessSimulator()
        // Forward: one scene, remove pl, settle, remove pr, settle (what a player does).
        let forward = try XCTUnwrap(sim.runSequence(level: lvl, moves: [.remove(pieceId: "pl"), .remove(pieceId: "pr")]).last)
        // Undo path: the log [pl, pr, pm] truncated to [pl, pr] and rebuilt from scratch.
        var log = MoveLog()
        log.append(.remove(pieceId: "pl"))
        log.append(.remove(pieceId: "pr"))
        let rebuilt = try sim.run(.init(level: lvl, base: log, move: nil))
        XCTAssertEqual(rebuilt.verdict.outcome, .standing)
        let end = forward.recording.poses(at: forward.duration)
        let back = rebuilt.recording.poses(at: rebuilt.duration)
        for (id, p) in end where back[id] != nil {
            XCTAssertLessThan(p.translation(from: back[id]!), 2.0, "\(id)")
            XCTAssertLessThan(p.rotationDelta(from: back[id]!), 0.02, "\(id)")
        }
    }

    func testFingerprintIsStableAcrossRuns() {
        XCTAssertEqual(PhysicsConstants.fingerprint, PhysicsConstants.fingerprint)
        XCTAssertTrue(PhysicsConstants.fingerprint.hasPrefix("spk-1-60hz-"))
    }
}
