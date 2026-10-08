import Foundation
import Testing
@testable import BalanceCore

@Suite("Level format")
struct LevelFormatTests {
    @Test func fixturesDecodeAndValidate() throws {
        for name in ["c-001", "c-003", "c-004"] {
            let level = try Fixtures.level(name)
            #expect(level.validate().isEmpty, "\(name): \(level.validate())")
            #expect(level.schema == 1)
        }
    }

    @Test func roundTripIsLossless() throws {
        let level = try Fixtures.level("c-004")
        let again = try Level.decode(from: level.encoded())
        #expect(again == level)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let json = """
        {"schema":1,"id":"x","pack":"pool","region":"stone_arch","index":3,"futureField":{"a":[1,2]},
         "goal":{"type":"removeTargetsKeepStanding","targetPieceIds":["a"],"moveBudget":2,"starThresholds":[1,2,2],"extra":true},
         "pieces":[{"id":"a","material":"wood","shape":{"type":"rect","w":10,"h":40},"position":{"x":0,"y":0},"sparkle":1}]}
        """
        let level = try Level.decode(from: Data(json.utf8))
        #expect(level.id == "x")
        #expect(level.joints.isEmpty)
        #expect(level.supportsAllowed == 0)
        #expect(level.gravity == PhysicsConstants.gravityDY)
        #expect(level.pieces[0].removable)
        #expect(level.pieces[0].isMonitored)
    }

    @Test func polygonPointsDecodeFromArrays() throws {
        let json = #"{"type":"polygon","points":[[-20,-14],[20,-14],[14,14],[-14,14]]}"#
        let shape = try JSONDecoder().decode(PieceShape.self, from: Data(json.utf8))
        guard case let .polygon(points) = shape else { Issue.record("expected polygon"); return }
        #expect(points.count == 4)
        #expect(points[2] == Vec2(14, 14))
        #expect(abs(shape.area - 952) < 0.001)
    }

    @Test func fixedPiecesAreNeverRemovable() throws {
        let json = #"{"id":"g","material":"stone","shape":{"type":"rect","w":10,"h":10},"position":{"x":0,"y":0},"fixed":true,"removable":true}"#
        let piece = try JSONDecoder().decode(Piece.self, from: Data(json.utf8))
        #expect(!piece.removable)
        #expect(!piece.isMonitored)
    }

    @Test func validationCatchesBrokenLevels() {
        var level = bridgeLevel()
        level.pieces.append(rectPiece("l", x: 0, y: 0, w: 1, h: 1))
        level.joints = [Joint(type: .pin, a: "beam", b: "ghost", anchor: .zero)]
        level.goal.starThresholds = [1, 2]
        let errors = level.validate()
        #expect(errors.contains(.duplicateId("l")))
        #expect(errors.contains(.missingPiece(context: "joint beam-ghost", id: "ghost")))
        #expect(errors.contains(.badThresholds))
    }

    @Test func removableIdsIncludeCuttableRopes() {
        var level = bridgeLevel()
        level.joints = [
            Joint(id: "rope1", type: .rope, a: "beam", b: "load", length: 30, removable: true),
            Joint(id: "pin1", type: .pin, a: "l", b: "beam", anchor: Vec2(-80, -20)),
        ]
        #expect(level.removableIds == ["l", "r", "beam", "load", "rope1"])
    }

    /// A rope leaves with either piece it ties: once that piece is gone it can't be cut any more
    /// (the solver must not offer it, the scene would refuse it).
    @Test func ropesGoWithTheirPieces() {
        var level = bridgeLevel()
        level.joints = [Joint(id: "rope1", type: .rope, a: "beam", b: "load", length: 30, removable: true)]
        #expect(level.availableRemovals(after: []) == ["l", "r", "beam", "load", "rope1"])
        #expect(level.availableRemovals(after: ["l"]) == ["r", "beam", "load", "rope1"])
        #expect(level.availableRemovals(after: ["beam"]) == ["l", "r", "load"])
        #expect(level.availableRemovals(after: ["load", "rope1"]) == ["l", "r", "beam"])
    }

    @Test func boundsAndFloor() throws {
        let level = try Fixtures.level("c-001")
        #expect(level.resolvedFloorY == -190)
        let b = level.bounds
        #expect(b.minY == -190)
        #expect(b.minX == -70 && b.maxX == 70)
    }
}
