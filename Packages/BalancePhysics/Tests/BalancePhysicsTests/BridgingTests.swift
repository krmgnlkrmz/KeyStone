import BalanceCore
@testable import BalancePhysics
import Testing

@Suite struct BridgingTests {
    @Test func vectorRoundTrip() {
        let v = Vec2(3, -4)
        #expect(Vec2(v.cgPoint) == v)
        #expect(PhysicsConstants.gravityVector.dy == -9.8)
    }
}
