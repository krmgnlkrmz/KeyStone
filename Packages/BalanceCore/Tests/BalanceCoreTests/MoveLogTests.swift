import Foundation
import Testing
@testable import BalanceCore

@Suite("Move log")
struct MoveLogTests {
    @Test func undoDropsOnlyTheLastMove() {
        var log = MoveLog()
        log.append(.remove(pieceId: "a"))
        log.append(.placeSupport(position: Vec2(16, -100), rotation: 0))
        log.append(.remove(pieceId: "b"))
        let undone = log.undo()
        #expect(undone?.kind == .remove(pieceId: "b"))
        #expect(log.count == 2)
        #expect(log.moves.map(\.index) == [0, 1])
        #expect(log.removedIds == ["a"])
        #expect(log.supportsPlaced == 1)
    }

    @Test func undoOnEmptyLogIsNil() {
        var log = MoveLog()
        #expect(log.undo() == nil)
        #expect(log.isEmpty)
    }

    @Test func stateKeyIgnoresOrder() {
        var a = MoveLog(), b = MoveLog()
        a.append(.remove(pieceId: "beam_7")); a.append(.remove(pieceId: "beam_3"))
        b.append(.remove(pieceId: "beam_3")); b.append(.remove(pieceId: "beam_7"))
        #expect(a.stateKey == b.stateKey)
        #expect(a.stateKey == "beam_3,beam_7")
        #expect(MoveLog().stateKey == "")
    }

    @Test func supportTokensRoundTrip() {
        let token = SupportToken.make(x: -40, rotation: 0)
        #expect(token == "+sup@-40")
        let tilted = SupportToken.make(x: 24, rotation: 15 * .pi / 180)
        #expect(tilted == "+sup@24r15")
        let parsed = SupportToken.parse(tilted)
        #expect(parsed?.x == 24)
        #expect(abs((parsed?.rotation ?? 0) - 15 * .pi / 180) < 1e-9)
        #expect(SupportToken.parse("beam") == nil)
    }

    @Test func truncationAndCodable() throws {
        var log = MoveLog()
        for id in ["a", "b", "c"] { log.append(.remove(pieceId: id)) }
        let short = log.truncated(to: 1)
        #expect(short.moves.map(\.token) == ["a"])
        let decoded = try JSONDecoder().decode(MoveLog.self, from: JSONEncoder().encode(log))
        #expect(decoded == log)
    }

    @Test func stateKeyHelpers() {
        #expect(StateKey.adding("b", to: "a,c") == "a,b,c")
        #expect(StateKey.tokens("") == [])
        #expect(StateKey.make(["+sup@8", "a"]) == "+sup@8,a")
    }
}
