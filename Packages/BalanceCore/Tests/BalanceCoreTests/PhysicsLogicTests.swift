import Foundation
import Testing
@testable import BalanceCore

@Suite("Settle verdict and goals")
struct SettleTests {
    @Test func smallSwayCountsAsStanding() {
        let v = SettleRules.verdict(metrics: [
            BodyMetrics(id: "a", peakTranslation: 10, peakRotation: 0.05),
            BodyMetrics(id: "b", peakTranslation: 13, peakRotation: 0.1),
        ])
        #expect(v.outcome == .standing)
        #expect(v.worstBodyId == "b")
        #expect(abs(v.margin - 2.0) < 1e-9)
    }

    @Test func translationOrRotationPastToleranceCollapses() {
        #expect(SettleRules.verdict(metrics: [BodyMetrics(id: "a", peakTranslation: 26, peakRotation: 0)]).outcome == .collapsed)
        #expect(SettleRules.verdict(metrics: [BodyMetrics(id: "a", peakTranslation: 1, peakRotation: 0.31)]).outcome == .collapsed)
    }

    @Test func dropTargetMayFallAlone() {
        let metrics = [
            BodyMetrics(id: "k", peakTranslation: 90, peakRotation: 0.8, finalDY: -88),
            BodyMetrics(id: "beam", peakTranslation: 3, peakRotation: 0.01),
        ]
        #expect(SettleRules.verdict(metrics: metrics, dropTargets: ["k"]).outcome == .dropped)
        let spill = metrics + [BodyMetrics(id: "post", peakTranslation: 40, peakRotation: 0.5)]
        #expect(SettleRules.verdict(metrics: spill, dropTargets: ["k"]).outcome == .collapsed)
        let stuck = [BodyMetrics(id: "k", peakTranslation: 4, peakRotation: 0, finalDY: -3)]
        #expect(SettleRules.verdict(metrics: stuck, dropTargets: ["k"]).outcome == .standing)
    }

    @Test func goalResults() {
        let goal = Goal(type: .removeTargetsKeepStanding, targetPieceIds: ["a", "b", "c"], requiredCount: 2, moveBudget: 3, starThresholds: [2, 3, 3])
        #expect(GoalRules.result(goal: goal, removed: ["a"], supportsPlaced: 0, movesMade: 1, outcome: .standing) == .continuePlaying)
        #expect(GoalRules.result(goal: goal, removed: ["a", "c"], supportsPlaced: 0, movesMade: 2, outcome: .standing) == .won)
        #expect(GoalRules.result(goal: goal, removed: ["a", "x", "y"], supportsPlaced: 0, movesMade: 3, outcome: .standing) == .outOfMoves)
        #expect(GoalRules.result(goal: goal, removed: ["a", "c"], supportsPlaced: 0, movesMade: 2, outcome: .collapsed) == .collapsed)

        let support = Goal(type: .placeSupportThenRemove, targetPieceIds: ["p"], moveBudget: 3, starThresholds: [2, 3, 3])
        #expect(GoalRules.result(goal: support, removed: ["p"], supportsPlaced: 0, movesMade: 1, outcome: .standing) == .continuePlaying)
        #expect(GoalRules.result(goal: support, removed: ["p"], supportsPlaced: 1, movesMade: 2, outcome: .standing) == .won)

        let drop = Goal(type: .dropOnlyTarget, targetPieceIds: ["k"], moveBudget: 2, starThresholds: [1, 2, 2])
        #expect(GoalRules.result(goal: drop, removed: ["s"], supportsPlaced: 0, movesMade: 1, outcome: .dropped) == .won)
        #expect(GoalRules.result(goal: drop, removed: ["s"], supportsPlaced: 0, movesMade: 2, outcome: .standing) == .outOfMoves)
    }

    @Test func poseRotationDeltaWraps() {
        let a = Pose(x: 0, y: 0, rotation: 3.1), b = Pose(x: 0, y: 0, rotation: -3.1)
        #expect(abs(a.rotationDelta(from: b) - (2 * .pi - 6.2)) < 1e-9)
    }

    @Test func pieceNouns() {
        #expect(PieceNaming.noun(for: rectPiece("p", x: 0, y: 0, w: 20, h: 90)) == .post)
        #expect(PieceNaming.noun(for: rectPiece("b", x: 0, y: 0, w: 200, h: 18)) == .beam)
        #expect(PieceNaming.noun(for: rectPiece("s", .steel, x: 0, y: 0, w: 14, h: 160)) == .column)
        #expect(PieceNaming.noun(for: rectPiece("k", .brass, x: 0, y: 0, w: 60, h: 40)) == .keystone)
        var rotatedBeam = rectPiece("r", x: 0, y: 0, w: 200, h: 18)
        rotatedBeam.rotation = .pi / 2
        #expect(PieceNaming.noun(for: rotatedBeam) == .post)
    }
}

@Suite("Blame heuristic")
struct CulpritTests {
    @Test func blamesTheBodyUnderTheOneThatTipped() {
        // "beam" tips over; "post" sits right under it; "far" is off to the side.
        let bounds: [String: Rect2] = [
            "beam": Rect2(minX: -100, minY: -10, maxX: 100, maxY: 10),
            "post": Rect2(minX: -10, minY: -40, maxX: 10, maxY: 40),
            "far": Rect2(minX: -10, minY: -40, maxX: 10, maxY: 40),
        ]
        var frames: [[String: Pose]] = []
        for i in 0..<40 {
            frames.append([
                "beam": Pose(x: 0, y: 50 - Double(i), rotation: Double(i) * 0.03),
                "post": Pose(x: 60, y: 0, rotation: Double(i) * 0.005),
                "far": Pose(x: 400, y: 0, rotation: 0),
            ])
        }
        let blamed = CulpritHeuristic.culprit(frames: frames, collapseFrame: 0, bounds: bounds, candidates: ["beam", "post", "far"])
        #expect(blamed == "post")
    }

    @Test func fallsBackToTheRotatingBody() {
        let bounds = ["solo": Rect2(minX: -10, minY: -10, maxX: 10, maxY: 10)]
        let frames = (0..<10).map { ["solo": Pose(x: 0, y: 0, rotation: Double($0) * 0.1)] }
        #expect(CulpritHeuristic.culprit(frames: frames, collapseFrame: 0, bounds: bounds, candidates: ["solo"]) == "solo")
        #expect(CulpritHeuristic.culprit(frames: [], collapseFrame: 0, bounds: bounds, candidates: ["solo"]) == nil)
    }
}

@Suite("Support geometry")
struct SupportGeometryTests {
    @Test func strutUnderTheBeamIsValid() throws {
        let level = try Fixtures.level("c-003")
        // Beam spans x -130…130 with its underside at y = -70 (prototype y 260, floor at -190).
        let pl = SupportGeometry.placement(atX: 3, level: level, removed: [])
        #expect(pl.x == 0)
        #expect(pl.targetId == "bm")
        #expect(pl.isValid)
        #expect(pl.bottomY == -190)
        #expect(abs(pl.topY - (-70)) < 0.001)
        #expect(pl.token == "+sup@0")
    }

    @Test func strutOverSolidGroundIsInvalid() throws {
        let level = try Fixtures.level("c-001")
        // Base block g1 sits on the floor across x -70…70.
        let pl = SupportGeometry.placement(atX: 0, level: level, removed: [])
        #expect(!pl.isValid)
        #expect(pl.targetId == "g1")
    }

    @Test func nothingAboveIsInvalid() throws {
        let level = try Fixtures.level("c-003")
        #expect(!SupportGeometry.placement(atX: 400, level: level, removed: []).isValid)
    }

    @Test func candidatesAreValidSnappedAndSnapTargets() throws {
        let level = try Fixtures.level("c-003")
        let c = SupportGeometry.candidates(level: level, removed: [])
        #expect(!c.isEmpty)
        for p in c {
            #expect(p.isValid)
            #expect(p.x.truncatingRemainder(dividingBy: PhysicsConstants.supportGrid) == 0)
        }
        let snapped = SupportGeometry.snapToCandidate(x: c[0].x + 5, candidates: c)
        #expect(snapped == c[0])
        #expect(SupportGeometry.snapToCandidate(x: 10_000, candidates: c) == nil)
    }

    @Test func removingAPieceChangesWhatAStrutReaches() throws {
        let level = try Fixtures.level("c-003")
        let x = -98.0 // under the left post p1 (x -110…-86)
        #expect(SupportGeometry.placement(atX: x, level: level, removed: []).targetId == "p1")
        #expect(SupportGeometry.placement(atX: x, level: level, removed: ["p1"]).targetId == "bm")
    }
}
