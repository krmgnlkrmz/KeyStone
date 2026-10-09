import BalanceCore
import CoreGraphics
import SpriteKit

/// Physics categories. Everything collides with everything; categories exist for queries.
public enum PhysicsCategory {
    public static let piece: UInt32 = 1 << 0
    public static let floor: UInt32 = 1 << 1
    public static let support: UInt32 = 1 << 2
    public static let all: UInt32 = 0xFFFF_FFFF
}

/// Name prefix for nodes that carry a piece's physics body. The rest of the name is the piece id.
public enum NodeNames {
    public static let piecePrefix = "piece:"
    public static let floor = "floor"
    public static func piece(_ id: String) -> String { piecePrefix + id }
    @MainActor
    public static func pieceId(of node: SKNode) -> String? {
        guard let name = node.name, name.hasPrefix(piecePrefix) else { return nil }
        return String(name.dropFirst(piecePrefix.count))
    }
}

/// The live structure: one node per present piece (and placed support), plus joints.
@MainActor
public final class BuiltStructure {
    public let level: Level
    /// Piece id → node carrying the physics body (position = centre, zRotation = rotation).
    public private(set) var nodes: [String: SKNode] = [:]
    /// Insertion order. SpriteKit's solver is sensitive to body order, so this never changes.
    public private(set) var order: [String] = []
    /// Live joints by id (`pin:a-b` for unnamed ones).
    public private(set) var joints: [String: (spec: Joint, joint: SKPhysicsJoint)] = [:]
    public private(set) var jointOrder: [String] = []
    /// Pose every piece is measured against.
    public private(set) var designPoses: [String: Pose] = [:]
    public private(set) var pieces: [String: Piece] = [:]
    public let floor: SKNode
    weak var physicsWorld: SKPhysicsWorld?

    init(level: Level, floor: SKNode, physicsWorld: SKPhysicsWorld) {
        self.level = level
        self.floor = floor
        self.physicsWorld = physicsWorld
    }

    public var presentIds: [String] { order.filter { nodes[$0] != nil } }

    /// Watched by the collapse decision: dynamic pieces whose `monitored` flag is on.
    public var monitoredIds: [String] {
        presentIds.filter { id in
            guard let p = pieces[id], let body = nodes[id]?.physicsBody else { return false }
            return p.isMonitored && body.isDynamic
        }
    }

    public func node(_ id: String) -> SKNode? { nodes[id] }
    public func piece(_ id: String) -> Piece? { pieces[id] }

    func register(piece: Piece, node: SKNode) {
        nodes[piece.id] = node
        pieces[piece.id] = piece
        order.append(piece.id)
        designPoses[piece.id] = Pose(piece.position, piece.rotation)
    }

    func register(jointId: String, spec: Joint, joint: SKPhysicsJoint) {
        joints[jointId] = (spec, joint)
        jointOrder.append(jointId)
    }

    /// Removes a piece (or cuts a rope when `id` names a removable joint). Returns the removed node.
    @discardableResult
    public func remove(_ id: String) -> SKNode? {
        if let j = joints[id] {
            physicsWorld?.remove(j.joint)
            joints[id] = nil
            return nil
        }
        guard let node = nodes[id] else { return nil }
        for (jid, j) in joints where j.spec.a == id || j.spec.b == id {
            physicsWorld?.remove(j.joint)
            joints[jid] = nil
        }
        node.removeFromParent()
        nodes[id] = nil
        return node
    }

    /// Current pose of a present piece.
    public func pose(_ id: String) -> Pose? {
        guard let n = nodes[id] else { return nil }
        return Pose(x: Double(n.position.x), y: Double(n.position.y), rotation: Double(n.zRotation))
    }

    /// World-space anchors of a rope, for drawing.
    public func ropeEndpoints(_ jointId: String) -> (CGPoint, CGPoint)? {
        guard let j = joints[jointId]?.spec, j.type == .rope,
              let a = nodes[j.a], let b = nodes[j.b] else { return nil }
        let pa = (j.anchorA ?? .zero).rotated(by: Double(a.zRotation)) + Vec2(a.position)
        let pb = (j.anchorB ?? .zero).rotated(by: Double(b.zRotation)) + Vec2(b.position)
        return (pa.cgPoint, pb.cgPoint)
    }
}

/// Level → SKNode tree + SKPhysicsBody. The only place physics bodies are configured.
@MainActor
public enum StructureSceneBuilder {
    /// Builds the floor, then pieces in file order, then supports in placement order, then joints in file order.
    /// - Parameters:
    ///   - removed: pieces and rope ids already removed by earlier moves.
    ///   - supports: struts already placed, in move order.
    ///   - parent: node that receives the bodies; it must sit at the scene origin with identity transform.
    public static func build(level: Level, removed: Set<String>, supports: [SupportPlacement],
                             parent: SKNode, physicsWorld: SKPhysicsWorld) -> BuiltStructure {
        physicsWorld.gravity = CGVector(dx: 0, dy: PhysicsConstants.gravityDY)
        physicsWorld.speed = 1.0

        let floor = makeFloor(y: level.resolvedFloorY)
        parent.addChild(floor)
        let structure = BuiltStructure(level: level, floor: floor, physicsWorld: physicsWorld)

        for piece in level.pieces where !removed.contains(piece.id) {
            let node = makeNode(for: piece)
            parent.addChild(node)
            structure.register(piece: piece, node: node)
        }
        for support in supports {
            addSupport(support, to: structure, parent: parent)
        }
        for joint in level.joints {
            if let id = joint.id, removed.contains(id) { continue }
            addJoint(joint, to: structure, physicsWorld: physicsWorld)
        }
        return structure
    }

    @discardableResult
    public static func addSupport(_ support: SupportPlacement, to structure: BuiltStructure, parent: SKNode) -> SKNode {
        var piece = support.asPiece
        piece.fixed = true
        piece.removable = false
        piece.monitored = false
        // Leave a hair of clearance so a sagging beam settles onto the strut instead of being pushed.
        let clearance = 0.5
        piece.shape = .rect(w: support.width, h: max(1, support.height - clearance))
        piece.position = Vec2(support.x, support.bottomY + (support.height - clearance) / 2)
        let node = makeNode(for: piece)
        node.physicsBody?.categoryBitMask = PhysicsCategory.support
        parent.addChild(node)
        structure.register(piece: piece, node: node)
        return node
    }

    public static func makeFloor(y: Double) -> SKNode {
        let floor = SKNode()
        floor.name = NodeNames.floor
        let body = SKPhysicsBody(edgeFrom: CGPoint(x: -4000, y: y), to: CGPoint(x: 4000, y: y))
        body.friction = CGFloat(PhysicsConstants.floorFriction)
        body.restitution = 0
        body.categoryBitMask = PhysicsCategory.floor
        body.collisionBitMask = PhysicsCategory.all
        body.contactTestBitMask = 0
        floor.physicsBody = body
        return floor
    }

    public static func makeNode(for piece: Piece) -> SKNode {
        let node = SKNode()
        node.name = NodeNames.piece(piece.id)
        node.position = piece.position.cgPoint
        node.zRotation = CGFloat(piece.rotation)
        node.physicsBody = makeBody(for: piece)
        return node
    }

    public static func makeBody(for piece: Piece) -> SKPhysicsBody {
        let body: SKPhysicsBody
        switch piece.shape {
        case let .rect(w, h):
            body = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
        case let .polygon(points):
            body = SKPhysicsBody(polygonFrom: convexPath(points))
        }
        let spec = PhysicsConstants.spec(for: piece.material)
        body.isDynamic = !piece.fixed
        body.affectedByGravity = true
        body.allowsRotation = true
        body.density = CGFloat(spec.density)
        body.friction = CGFloat(spec.friction)
        body.restitution = CGFloat(spec.restitution)
        body.linearDamping = CGFloat(spec.linearDamping)
        body.angularDamping = CGFloat(spec.angularDamping)
        let (w, h) = piece.shape.size
        body.usesPreciseCollisionDetection = min(w, h) < PhysicsConstants.preciseCollisionMaxThickness
        body.categoryBitMask = PhysicsCategory.piece
        body.collisionBitMask = PhysicsCategory.all
        body.contactTestBitMask = 0
        return body
    }

    /// SpriteKit wants counter-clockwise winding.
    static func convexPath(_ points: [Vec2]) -> CGPath {
        var pts = points
        var area = 0.0
        for i in pts.indices {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            area += p.x * q.y - q.x * p.y
        }
        if area < 0 { pts.reverse() }
        let path = CGMutablePath()
        path.addLines(between: pts.map(\.cgPoint))
        path.closeSubpath()
        return path
    }

    static func addJoint(_ joint: Joint, to structure: BuiltStructure, physicsWorld: SKPhysicsWorld) {
        guard let na = structure.node(joint.a), let nb = structure.node(joint.b),
              let ba = na.physicsBody, let bb = nb.physicsBody else { return }
        let id = joint.id ?? "\(joint.type.rawValue):\(joint.a)-\(joint.b)"
        switch joint.type {
        case .pin:
            let anchor = joint.anchor ?? Vec2((Double(na.position.x) + Double(nb.position.x)) / 2,
                                              (Double(na.position.y) + Double(nb.position.y)) / 2)
            let pin = SKPhysicsJointPin.joint(withBodyA: ba, bodyB: bb, anchor: anchor.cgPoint)
            pin.frictionTorque = 0
            physicsWorld.add(pin)
            structure.register(jointId: id, spec: joint, joint: pin)
        case .rope:
            let pa = (joint.anchorA ?? .zero).rotated(by: Double(na.zRotation)) + Vec2(na.position)
            let pb = (joint.anchorB ?? .zero).rotated(by: Double(nb.zRotation)) + Vec2(nb.position)
            let limit = SKPhysicsJointLimit.joint(withBodyA: ba, bodyB: bb, anchorA: pa.cgPoint, anchorB: pb.cgPoint)
            limit.maxLength = CGFloat(joint.length ?? (pb - pa).length)
            physicsWorld.add(limit)
            structure.register(jointId: id, spec: joint, joint: limit)
        }
    }
}
