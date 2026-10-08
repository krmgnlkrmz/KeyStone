import Foundation

// MARK: - Geometry primitives

/// A 2D value in design points. Y grows upwards (SpriteKit convention).
public struct Vec2: Codable, Sendable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func rotated(by angle: Double) -> Vec2 {
        let c = cos(angle), s = sin(angle)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    public var description: String { "(\(x), \(y))" }

    // Accept both {"x":1,"y":2} and [1,2].
    public init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            x = try array.decode(Double.self)
            y = try array.decode(Double.self)
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try c.decode(Double.self, forKey: .x)
            y = try c.decode(Double.self, forKey: .y)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
    }

    private enum CodingKeys: String, CodingKey { case x, y }
}

/// Axis-aligned rectangle in design points (y up).
public struct Rect2: Codable, Sendable, Hashable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }

    public func union(_ o: Rect2) -> Rect2 {
        Rect2(minX: min(minX, o.minX), minY: min(minY, o.minY), maxX: max(maxX, o.maxX), maxY: max(maxY, o.maxY))
    }

    public static func enclosing(_ points: [Vec2]) -> Rect2 {
        var r = Rect2(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)
        for p in points {
            r.minX = min(r.minX, p.x); r.minY = min(r.minY, p.y)
            r.maxX = max(r.maxX, p.x); r.maxY = max(r.maxY, p.y)
        }
        return r
    }
}

// MARK: - Materials

/// Physical numbers for a material live only in `PhysicsConstants`; level files name the material.
public enum Material: String, Codable, Sendable, CaseIterable {
    case wood, stone, steel, brass, rope
}

// MARK: - Pieces

public enum PieceShape: Codable, Sendable, Hashable {
    case rect(w: Double, h: Double)
    /// Convex polygon, counter-clockwise or clockwise, in the piece's local frame.
    case polygon(points: [Vec2])

    private enum CodingKeys: String, CodingKey { case type, w, h, points }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "rect":
            self = .rect(w: try c.decode(Double.self, forKey: .w), h: try c.decode(Double.self, forKey: .h))
        case "polygon":
            self = .polygon(points: try c.decode([Vec2].self, forKey: .points))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown shape type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .rect(w, h):
            try c.encode("rect", forKey: .type)
            try c.encode(w, forKey: .w)
            try c.encode(h, forKey: .h)
        case let .polygon(points):
            try c.encode("polygon", forKey: .type)
            try c.encode(points.map { [$0.x, $0.y] }, forKey: .points)
        }
    }

    /// Outline in the piece's local frame (unrotated).
    public var localOutline: [Vec2] {
        switch self {
        case let .rect(w, h):
            return [Vec2(-w / 2, -h / 2), Vec2(w / 2, -h / 2), Vec2(w / 2, h / 2), Vec2(-w / 2, h / 2)]
        case let .polygon(points):
            return points
        }
    }

    /// Width and height of the unrotated local bounds.
    public var size: (w: Double, h: Double) {
        let r = Rect2.enclosing(localOutline)
        return (r.width, r.height)
    }

    public var area: Double {
        let pts = localOutline
        var a = 0.0
        for i in pts.indices {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            a += p.x * q.y - q.x * p.y
        }
        return abs(a) / 2
    }
}

public struct Piece: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var material: Material
    public var shape: PieceShape
    /// Centre of the piece in design points.
    public var position: Vec2
    /// Radians, counter-clockwise.
    public var rotation: Double
    /// Static body (`isDynamic = false`).
    public var fixed: Bool
    /// Whether the player may remove it.
    public var removable: Bool
    /// Whether the collapse decision watches this body. Defaults to `!fixed`.
    public var monitored: Bool?

    public init(id: String, material: Material, shape: PieceShape, position: Vec2, rotation: Double = 0,
                fixed: Bool = false, removable: Bool = true, monitored: Bool? = nil) {
        self.id = id; self.material = material; self.shape = shape; self.position = position
        self.rotation = rotation; self.fixed = fixed; self.removable = removable && !fixed; self.monitored = monitored
    }

    private enum CodingKeys: String, CodingKey { case id, material, shape, position, rotation, fixed, removable, monitored }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        material = try c.decode(Material.self, forKey: .material)
        shape = try c.decode(PieceShape.self, forKey: .shape)
        position = try c.decode(Vec2.self, forKey: .position)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        fixed = try c.decodeIfPresent(Bool.self, forKey: .fixed) ?? false
        removable = (try c.decodeIfPresent(Bool.self, forKey: .removable) ?? !fixed) && !fixed
        monitored = try c.decodeIfPresent(Bool.self, forKey: .monitored)
    }

    public var isMonitored: Bool { monitored ?? !fixed }

    /// World-space outline at the design pose.
    public var worldOutline: [Vec2] {
        shape.localOutline.map { $0.rotated(by: rotation) + position }
    }

    public var worldBounds: Rect2 { Rect2.enclosing(worldOutline) }
}

// MARK: - Joints

public enum JointType: String, Codable, Sendable {
    /// Rotating pin at a world anchor.
    case pin
    /// Maximum-distance rope between two anchors. A rope can be cut when `removable`.
    case rope
}

public struct Joint: Codable, Sendable, Hashable {
    public var id: String?
    public var type: JointType
    public var a: String
    public var b: String
    /// Pin: world anchor at the design pose.
    public var anchor: Vec2?
    /// Rope: anchor offsets in each body's local frame (default: centre).
    public var anchorA: Vec2?
    public var anchorB: Vec2?
    /// Rope: maximum length. Defaults to the anchors' design distance.
    public var length: Double?
    /// Ropes only: the player may cut it. Cutting counts as a move and uses the joint id.
    public var removable: Bool?

    public init(id: String? = nil, type: JointType, a: String, b: String, anchor: Vec2? = nil,
                anchorA: Vec2? = nil, anchorB: Vec2? = nil, length: Double? = nil, removable: Bool? = nil) {
        self.id = id; self.type = type; self.a = a; self.b = b; self.anchor = anchor
        self.anchorA = anchorA; self.anchorB = anchorB; self.length = length; self.removable = removable
    }

    public var isRemovable: Bool { type == .rope && (removable ?? false) && id != nil }
}

// MARK: - Goal

public enum GoalType: String, Codable, Sendable {
    /// Remove the target pieces (or `requiredCount` of them); everything else stays up.
    case removeTargetsKeepStanding
    /// Only the target falls; every other monitored body stays within tolerance.
    case dropOnlyTarget
    /// Same as remove-targets, but at least one support has to be placed first.
    case placeSupportThenRemove
}

public struct Goal: Codable, Sendable, Hashable {
    public var type: GoalType
    public var targetPieceIds: [String]
    /// How many of the targets must be removed. Defaults to all of them.
    public var requiredCount: Int?
    public var moveBudget: Int
    /// Upper move bounds for 3, 2 and 1 stars. Stored in any order; read through `normalizedThresholds`.
    public var starThresholds: [Int]

    public init(type: GoalType, targetPieceIds: [String], requiredCount: Int? = nil, moveBudget: Int, starThresholds: [Int]) {
        self.type = type; self.targetPieceIds = targetPieceIds; self.requiredCount = requiredCount
        self.moveBudget = moveBudget; self.starThresholds = starThresholds
    }

    public var effectiveRequiredCount: Int {
        switch type {
        case .dropOnlyTarget: return 1
        default: return min(requiredCount ?? targetPieceIds.count, targetPieceIds.count)
        }
    }

    /// Ascending: [3★ bound, 2★ bound, 1★ bound].
    public var normalizedThresholds: [Int] { StarRules.normalize(starThresholds, budget: moveBudget) }
}

// MARK: - Annotation (produced offline by LevelForge)

/// Safe/unsafe neighbourhood of one state, as measured by the solver.
public struct StateMoves: Codable, Sendable, Hashable {
    /// Removed piece ids (and support tokens), sorted and comma-joined. "" is the start.
    public var state: String
    /// Moves that keep the structure standing.
    public var safe: [String]
    /// Move → id of the piece that gave way. JSON key `unsafe`.
    public var unsafeMoves: [String: String]
    /// Move → peak displacement / tolerance. < 1 for safe moves, ≥ 1 for unsafe ones.
    public var severity: [String: Double]?
    /// Moves that complete the goal from this state (e.g. the clean drop).
    public var win: [String]?

    public init(state: String, safe: [String], unsafe unsafeMoves: [String: String], severity: [String: Double]? = nil, win: [String]? = nil) {
        self.state = state; self.safe = safe; self.unsafeMoves = unsafeMoves; self.severity = severity; self.win = win
    }

    private enum CodingKeys: String, CodingKey {
        case state, safe, unsafeMoves = "unsafe", severity, win
    }
}

public struct Annotation: Codable, Sendable, Hashable {
    public var solutionPath: [String]
    public var stateMoves: [StateMoves]
    public var verifiedAt: String
    public var engineFingerprint: String
    /// Worst-case distance from the decision threshold over all validation runs (≥ 1.4 to ship).
    public var marginRatio: Double?
    /// Solver difficulty estimate: explored states / branching, informational.
    public var difficulty: Double?

    public init(solutionPath: [String], stateMoves: [StateMoves], verifiedAt: String, engineFingerprint: String,
                marginRatio: Double? = nil, difficulty: Double? = nil) {
        self.solutionPath = solutionPath; self.stateMoves = stateMoves; self.verifiedAt = verifiedAt
        self.engineFingerprint = engineFingerprint; self.marginRatio = marginRatio; self.difficulty = difficulty
    }
}

// MARK: - Level

public enum Pack: String, Codable, Sendable {
    case curated, pool
}

public struct Level: Codable, Sendable, Identifiable, Hashable {
    public static let currentSchema = 1

    public var schema: Int
    public var id: String
    public var pack: Pack
    public var region: String
    public var index: Int
    public var seed: UInt64?
    /// m/s², SpriteKit convention. Kept per level for format compatibility; must equal PhysicsConstants.gravityDY to verify.
    public var gravity: Double
    /// Top of the floor in design points. Defaults to the lowest piece bottom.
    public var floorY: Double?
    /// Localised display name, keyed by language code ("en", "tr").
    public var name: [String: String]?
    /// Localised goal sentence override. When absent the app builds one from the goal.
    public var goalText: [String: String]?
    /// Tutorial overlay: 1 tap, 2 collapse, 3 support.
    public var tutorial: Int?
    public var goal: Goal
    public var supportsAllowed: Int
    public var pieces: [Piece]
    public var joints: [Joint]
    public var annotation: Annotation?

    public init(schema: Int = Level.currentSchema, id: String, pack: Pack, region: String, index: Int, seed: UInt64? = nil,
                gravity: Double = PhysicsConstants.gravityDY, floorY: Double? = nil, name: [String: String]? = nil,
                goalText: [String: String]? = nil, tutorial: Int? = nil, goal: Goal, supportsAllowed: Int = 0,
                pieces: [Piece], joints: [Joint] = [], annotation: Annotation? = nil) {
        self.schema = schema; self.id = id; self.pack = pack; self.region = region; self.index = index; self.seed = seed
        self.gravity = gravity; self.floorY = floorY; self.name = name; self.goalText = goalText; self.tutorial = tutorial
        self.goal = goal; self.supportsAllowed = supportsAllowed; self.pieces = pieces; self.joints = joints
        self.annotation = annotation
    }

    private enum CodingKeys: String, CodingKey {
        case schema, id, pack, region, index, seed, gravity, floorY, name, goalText, tutorial, goal, supportsAllowed, pieces, joints, annotation
    }

    // Unknown keys are ignored by Codable; missing optional keys fall back to defaults so older files keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        id = try c.decode(String.self, forKey: .id)
        pack = try c.decodeIfPresent(Pack.self, forKey: .pack) ?? .pool
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? Region.woodScaffold.rawValue
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed)
        gravity = try c.decodeIfPresent(Double.self, forKey: .gravity) ?? PhysicsConstants.gravityDY
        floorY = try c.decodeIfPresent(Double.self, forKey: .floorY)
        name = try c.decodeIfPresent([String: String].self, forKey: .name)
        goalText = try c.decodeIfPresent([String: String].self, forKey: .goalText)
        tutorial = try c.decodeIfPresent(Int.self, forKey: .tutorial)
        goal = try c.decode(Goal.self, forKey: .goal)
        supportsAllowed = try c.decodeIfPresent(Int.self, forKey: .supportsAllowed) ?? 0
        pieces = try c.decode([Piece].self, forKey: .pieces)
        joints = try c.decodeIfPresent([Joint].self, forKey: .joints) ?? []
        annotation = try c.decodeIfPresent(Annotation.self, forKey: .annotation)
    }

    public func piece(_ id: String) -> Piece? { pieces.first { $0.id == id } }

    /// Ids the player can act on: removable pieces and cuttable ropes, in file order.
    public var removableIds: [String] {
        pieces.filter(\.removable).map(\.id) + joints.filter(\.isRemovable).compactMap(\.id)
    }

    public var resolvedFloorY: Double {
        if let floorY { return floorY }
        return pieces.map { $0.worldBounds.minY }.min() ?? 0
    }

    /// Bounds of every piece at the design pose, including the floor line.
    public var bounds: Rect2 {
        var r = pieces.map(\.worldBounds).reduce(nil as Rect2?) { acc, b in acc?.union(b) ?? b }
            ?? Rect2(minX: -150, minY: -190, maxX: 150, maxY: 190)
        r.minY = min(r.minY, resolvedFloorY)
        return r
    }

    public func localizedName(language: String) -> String? {
        guard let name else { return nil }
        return name[language] ?? name["en"]
    }

    public func localizedGoalText(language: String) -> String? {
        guard let goalText else { return nil }
        return goalText[language] ?? goalText["en"]
    }

    public static func decode(from data: Data) throws -> Level {
        try JSONDecoder().decode(Level.self, from: data)
    }

    public func encoded(pretty: Bool = true) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try e.encode(self)
    }
}

// MARK: - Validation

public enum LevelValidationError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case duplicateId(String)
    case missingPiece(context: String, id: String)
    case targetNotRemovable(String)
    case badThresholds
    case badBudget
    case polygonTooSmall(String)
    case noSupportsForSupportGoal
    case dropGoalNeedsOneTarget

    public var description: String {
        switch self {
        case let .unsupportedSchema(s): return "unsupported schema \(s)"
        case let .duplicateId(id): return "duplicate id \(id)"
        case let .missingPiece(ctx, id): return "\(ctx) references missing piece \(id)"
        case let .targetNotRemovable(id): return "target \(id) is not removable"
        case .badThresholds: return "starThresholds must hold 3 values within the move budget"
        case .badBudget: return "moveBudget must be ≥ 1"
        case let .polygonTooSmall(id): return "polygon \(id) needs ≥ 3 points"
        case .noSupportsForSupportGoal: return "placeSupportThenRemove needs supportsAllowed ≥ 1"
        case .dropGoalNeedsOneTarget: return "dropOnlyTarget needs exactly one target"
        }
    }
}

extension Level {
    public func validate() -> [LevelValidationError] {
        var errors: [LevelValidationError] = []
        if schema > Level.currentSchema { errors.append(.unsupportedSchema(schema)) }
        var seen = Set<String>()
        for id in pieces.map(\.id) + joints.compactMap(\.id) where !seen.insert(id).inserted {
            errors.append(.duplicateId(id))
        }
        let pieceIds = Set(pieces.map(\.id))
        for j in joints {
            for end in [j.a, j.b] where !pieceIds.contains(end) {
                errors.append(.missingPiece(context: "joint \(j.id ?? "\(j.a)-\(j.b)")", id: end))
            }
        }
        for p in pieces {
            if case let .polygon(points) = p.shape, points.count < 3 { errors.append(.polygonTooSmall(p.id)) }
        }
        let removable = Set(removableIds)
        for t in goal.targetPieceIds {
            if !pieceIds.contains(t) && !removable.contains(t) {
                errors.append(.missingPiece(context: "goal", id: t))
            } else if goal.type != .dropOnlyTarget && !removable.contains(t) {
                errors.append(.targetNotRemovable(t))
            }
        }
        if goal.moveBudget < 1 { errors.append(.badBudget) }
        let th = goal.starThresholds
        if th.count != 3 || th.contains(where: { $0 < 1 || $0 > goal.moveBudget }) { errors.append(.badThresholds) }
        if goal.type == .placeSupportThenRemove && supportsAllowed < 1 { errors.append(.noSupportsForSupportGoal) }
        if goal.type == .dropOnlyTarget && goal.targetPieceIds.count != 1 { errors.append(.dropGoalNeedsOneTarget) }
        return errors
    }
}
