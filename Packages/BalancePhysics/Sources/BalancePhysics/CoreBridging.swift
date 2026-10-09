import BalanceCore
import CoreGraphics
import SpriteKit

/// Conversions between BalanceCore's platform-free values and CoreGraphics / SpriteKit.
extension Vec2 {
    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    public var cgVector: CGVector { CGVector(dx: x, dy: y) }
    public init(_ p: CGPoint) { self.init(Double(p.x), Double(p.y)) }
}

extension PhysicsConstants {
    public static var gravityVector: CGVector { CGVector(dx: 0, dy: gravityDY) }
}
