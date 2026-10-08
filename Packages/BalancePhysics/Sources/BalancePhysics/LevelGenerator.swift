import BalanceCore
import Foundation
import GameplayKit

/// Seeded, archetype-based structure generator for LevelForge.
///
/// Random structures are mostly rubble or boring, so every candidate starts from a hand-made
/// skeleton (table, tower, lintel, counterweight, bridge, hanger, pyramid) and only jitters its
/// parameters: lengths, materials, piece counts, load positions. The same seed always gives the
/// same level. Whether a candidate ships is decided by `SolutionSolver`, never here.
public struct LevelGenerator {
    public enum Archetype: String, CaseIterable, Sendable, Codable {
        case table, tower, lintel, counterweight, bridge, hanger, pyramid

        public var regions: [Region] {
            switch self {
            case .table: return [.woodScaffold, .ironTruss]
            case .tower: return [.woodScaffold, .ironTruss, .stoneArch]
            case .lintel: return [.stoneArch, .keystone]
            case .counterweight: return [.counterweight, .steelCrane]
            case .bridge: return [.counterweight]
            case .hanger: return [.ropeBridge, .steelCrane]
            case .pyramid: return [.keystone, .stoneArch]
            }
        }
    }

    public static let floorY: Double = -190

    public let seed: UInt64
    private let random: GKMersenneTwisterRandomSource

    public init(seed: UInt64) {
        self.seed = seed
        random = GKMersenneTwisterRandomSource(seed: seed)
    }

    /// Archetype chosen from the seed when none is requested.
    public func make(archetype requested: Archetype? = nil, region requestedRegion: Region? = nil, pack: Pack = .pool, index: Int = 0) -> Level {
        let archetype = requested ?? pick(Archetype.allCases)
        let region = requestedRegion ?? pick(archetype.regions)
        var b = Builder(floor: Self.floorY)
        var goal: Goal
        var supports = 0
        switch archetype {
        case .table: goal = table(&b, steel: region == .ironTruss)
        case .tower: goal = tower(&b, steel: region == .ironTruss, stone: region == .stoneArch)
        case .lintel: goal = lintel(&b)
        case .counterweight: (goal, supports) = counterweight(&b)
        case .bridge: (goal, supports) = bridge(&b)
        case .hanger: goal = hanger(&b, crane: region == .steelCrane)
        case .pyramid: goal = pyramid(&b)
        }
        let removable = b.pieces.filter(\.removable).count + b.joints.filter(\.isRemovable).count
        goal.moveBudget = min(max(goal.effectiveRequiredCount + 1, removable), 7)
        goal.starThresholds = [goal.moveBudget, goal.moveBudget, goal.moveBudget]
        let prefix = pack == .curated ? "c" : "p"
        return Level(id: "\(prefix)-\(archetype.rawValue)-\(seed)", pack: pack, region: region.rawValue, index: index, seed: seed,
                     floorY: Self.floorY, goal: goal, supportsAllowed: supports, pieces: b.pieces, joints: b.joints)
    }

    // MARK: Random helpers

    private func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + random.nextInt(upperBound: r.count) }
    private func double(_ r: ClosedRange<Double>) -> Double { r.lowerBound + Double(random.nextUniform()) * (r.upperBound - r.lowerBound) }
    private func chance(_ p: Double) -> Bool { Double(random.nextUniform()) < p }
    private func pick<T>(_ xs: [T]) -> T { xs[random.nextInt(upperBound: xs.count)] }
    /// Rounded to whole points so files stay readable and bodies touch exactly.
    private func q(_ v: Double) -> Double { v.rounded() }

    // MARK: Builder

    struct Builder {
        let floor: Double
        var pieces: [Piece] = []
        var joints: [Joint] = []
        var counter: [String: Int] = [:]

        mutating func nextId(_ prefix: String) -> String {
            counter[prefix, default: 0] += 1
            return "\(prefix)\(counter[prefix]!)"
        }

        /// Adds a rectangle whose bottom edge sits at `bottom`. Returns it.
        @discardableResult
        mutating func rect(_ prefix: String, _ m: Material, x: Double, bottom: Double, w: Double, h: Double,
                           fixed: Bool = false, removable: Bool = true) -> Piece {
            let p = Piece(id: nextId(prefix), material: m, shape: .rect(w: w, h: h), position: Vec2(x, bottom + h / 2),
                          fixed: fixed, removable: removable && !fixed)
            pieces.append(p)
            return p
        }

        @discardableResult
        mutating func keystone(x: Double, bottom: Double, w: Double, h: Double) -> Piece {
            let pts = [Vec2(-0.3 * w, -h / 2), Vec2(0.3 * w, -h / 2), Vec2(w / 2, h / 2), Vec2(-w / 2, h / 2)]
            let p = Piece(id: "k", material: .brass, shape: .polygon(points: pts), position: Vec2(x, bottom + h / 2),
                          fixed: false, removable: false)
            pieces.append(p)
            return p
        }
    }

    static func top(_ p: Piece) -> Double { p.worldBounds.maxY }

    // MARK: Archetypes

    /// Posts under a beam with loads on top; optional second tier.
    private func table(_ b: inout Builder, steel: Bool) -> Goal {
        let span = q(double(180...260))
        let posts = int(2...4)
        let postH = q(double(60...110))
        let postW = q(double(18...26))
        let postMat: Material = steel ? .steel : .wood
        var postIds: [String] = []
        for i in 0..<posts {
            var x = -span / 2 + postW / 2 + (span - postW) * Double(i) / Double(posts - 1)
            if i > 0 && i < posts - 1 { x += q(double(-20...20)) }
            postIds.append(b.rect("post", postMat, x: q(x), bottom: b.floor, w: postW, h: postH).id)
        }
        let beamH = q(double(14...20))
        let beam = b.rect("beam", steel ? .steel : .wood, x: 0, bottom: b.floor + postH, w: span + q(double(10...30)), h: beamH)
        var loadIds: [String] = []
        let loads = int(1...3)
        var used: [ClosedRange<Double>] = []
        for _ in 0..<loads {
            let w = q(double(30...56)), h = q(double(28...50))
            for _ in 0..<8 {
                let x = q(double(-span / 2 + w / 2 ... span / 2 - w / 2))
                let r = (x - w / 2 - 4)...(x + w / 2 + 4)
                if used.allSatisfy({ !$0.overlaps(r) }) {
                    used.append(r)
                    loadIds.append(b.rect("load", .stone, x: x, bottom: Self.top(beam), w: w, h: h).id)
                    break
                }
            }
        }
        if chance(0.4), let first = loadIds.first, let load = b.pieces.first(where: { $0.id == first }) {
            // Second tier: a short beam on the first load with a small block.
            let w2 = q(double(60...110))
            let beam2 = b.rect("beam", .wood, x: load.position.x, bottom: Self.top(load), w: w2, h: 14)
            loadIds.append(b.rect("load", .stone, x: q(load.position.x + double(-w2 / 4 ... w2 / 4)), bottom: Self.top(beam2), w: 28, h: 28).id)
        }
        switch int(0...2) {
        case 0 where posts >= 3:
            return Goal(type: .removeTargetsKeepStanding, targetPieceIds: postIds, requiredCount: posts - 2, moveBudget: 0, starThresholds: [])
        case 1:
            return Goal(type: .removeTargetsKeepStanding, targetPieceIds: loadIds, moveBudget: 0, starThresholds: [])
        default:
            let wood = b.pieces.filter { $0.material == .wood && $0.removable }.map(\.id)
            return Goal(type: .removeTargetsKeepStanding, targetPieceIds: wood.isEmpty ? loadIds : wood,
                        requiredCount: max(1, min(wood.count - 1, int(2...3))), moveBudget: 0, starThresholds: [])
        }
    }

    /// Alternating beams and posts, Jenga-like.
    private func tower(_ b: inout Builder, steel: Bool, stone: Bool) -> Goal {
        let levels = int(2...3)
        var bottom = b.floor
        let width = q(double(120...200))
        var all: [String] = []
        for level in 0..<levels {
            let h = q(double(50...80))
            let n = level == 0 ? int(2...3) : 2
            let w = q(double(16...24))
            for i in 0..<n {
                let x = -width / 2 + w / 2 + (width - w) * Double(i) / Double(n - 1)
                all.append(b.rect("post", stone ? .stone : (steel ? .steel : .wood), x: q(x + double(-6...6)), bottom: bottom, w: w, h: h).id)
            }
            bottom += h
            let beam = b.rect("beam", steel ? .steel : .wood, x: q(double(-10...10)), bottom: bottom, w: width + q(double(10...40)), h: 16)
            all.append(beam.id)
            bottom = Self.top(beam)
        }
        let cap = b.rect("load", .stone, x: q(double(-30...30)), bottom: bottom, w: q(double(36...60)), h: q(double(30...44)))
        let n = int(2...3)
        return Goal(type: .removeTargetsKeepStanding, targetPieceIds: all.filter { !$0.hasPrefix("beam") } + [cap.id],
                    requiredCount: n, moveBudget: 0, starThresholds: [])
    }

    /// Fixed bases, pillars, a lintel and a keystone resting on blocks: drop only the keystone.
    private func lintel(_ b: inout Builder) -> Goal {
        let half = q(double(70...110))
        let baseW = q(double(50...70)), baseH = q(double(40...60))
        let bl = b.rect("base", .stone, x: -half, bottom: b.floor, w: baseW, h: baseH, fixed: true)
        b.rect("base", .stone, x: half, bottom: b.floor, w: baseW, h: baseH, fixed: true)
        let pillarH = q(double(60...100)), pillarW = q(double(22...30))
        b.rect("pillar", chance(0.5) ? .wood : .stone, x: -half, bottom: Self.top(bl), w: pillarW, h: pillarH)
        b.rect("pillar", chance(0.5) ? .wood : .stone, x: half, bottom: Self.top(bl), w: pillarW, h: pillarH)
        if chance(0.5) {
            b.rect("column", .steel, x: q(double(-10...10)), bottom: b.floor, w: 14, h: baseH + pillarH)
        }
        let lintelW = 2 * half + q(double(40...70))
        let beam = b.rect("beam", .wood, x: 0, bottom: Self.top(bl) + pillarH, w: lintelW, h: q(double(16...20)))
        let blocks = int(2...3)
        let kw = q(double(80...130)), kh = q(double(34...44))
        let blockW = q(double(24...32)), blockH = q(double(36...50))
        for i in 0..<blocks {
            let x = blocks == 1 ? 0 : -kw / 2 + blockW / 2 + 6 + (kw - blockW - 12) * Double(i) / Double(blocks - 1)
            b.rect("block", .stone, x: q(x), bottom: Self.top(beam), w: blockW, h: blockH)
        }
        b.keystone(x: 0, bottom: Self.top(beam) + blockH, w: kw, h: kh)
        if chance(0.4) {
            b.rect("weight", .stone, x: q(double(-lintelW / 2 + 20 ... -kw / 2 - 20)), bottom: Self.top(beam), w: 26, h: 26)
        }
        return Goal(type: .dropOnlyTarget, targetPieceIds: ["k"], moveBudget: 0, starThresholds: [])
    }

    /// A beam balanced on one column with weights on both sides: remove the weights in a safe order.
    private func counterweight(_ b: inout Builder) -> (Goal, Int) {
        let colW = q(double(16...24)), colH = q(double(90...130))
        let col = b.rect("column", .steel, x: 0, bottom: b.floor, w: colW, h: colH)
        let beamW = q(double(240...280))
        let beam = b.rect("beam", .wood, x: 0, bottom: Self.top(col), w: beamW, h: 16)
        let pairs = int(2...3)
        var targets: [String] = []
        var torque = 0.0
        var leftXs: [Double] = [], sizes: [Double] = []
        for i in 0..<pairs {
            let s = q(double(24...34))
            let x = -beamW / 2 + 12 + s / 2 + Double(i) * (s + q(double(6...14)))
            guard x < -colW else { break }
            leftXs.append(x); sizes.append(s)
            targets.append(b.rect("w", .stone, x: q(x), bottom: Self.top(beam), w: s, h: s).id)
            torque += x * s * s
        }
        // Mirror with a different arrangement whose torque cancels the left side.
        var remaining = -torque
        for (i, s0) in sizes.enumerated() {
            let s = i == sizes.count - 1 ? s0 : q(double(24...34))
            let x = i == sizes.count - 1 ? remaining / (s * s) : -leftXs[i] + q(double(-8...8))
            guard x > colW, x < beamW / 2 - s / 2 else { continue }
            targets.append(b.rect("w", .stone, x: q(x), bottom: Self.top(beam), w: s, h: s).id)
            remaining -= x * s * s
        }
        let pad = b.rect("pad", .wood, x: 0, bottom: Self.top(beam), w: 30, h: 30)
        if chance(0.6) { b.keystone(x: 0, bottom: Self.top(pad), w: 60, h: 40) }
        let supports = chance(0.5) ? 1 : 0
        return (Goal(type: .removeTargetsKeepStanding, targetPieceIds: targets, moveBudget: 0, starThresholds: []), supports)
    }

    /// Long beam on two posts with a heavy load: place a strut, then take the posts away.
    private func bridge(_ b: inout Builder) -> (Goal, Int) {
        let span = q(double(220...270))
        let postH = q(double(90...130))
        let p1 = b.rect("post", .wood, x: -span / 2 + 12, bottom: b.floor, w: 24, h: postH)
        let p2 = b.rect("post", .wood, x: span / 2 - 12, bottom: b.floor, w: 24, h: postH)
        let beam = b.rect("beam", .wood, x: 0, bottom: Self.top(p1), w: span + 20, h: 18)
        let lx = q(double(-span / 4 ... span / 4))
        b.rect("load", .stone, x: lx, bottom: Self.top(beam), w: q(double(44...60)), h: q(double(40...56)))
        if chance(0.5) { b.rect("load", .stone, x: q(-lx * 0.6), bottom: Self.top(beam), w: 26, h: 26) }
        return (Goal(type: .placeSupportThenRemove, targetPieceIds: [p1.id, p2.id], moveBudget: 0, starThresholds: []), 1)
    }

    /// A beam hanging from a fixed gantry on two ropes, loads on the beam, a post underneath.
    private func hanger(_ b: inout Builder, crane: Bool) -> Goal {
        let mastX = q(double(-130 ... -100))
        let mastH = q(double(250...300))
        let mast = b.rect("mast", .steel, x: mastX, bottom: b.floor, w: 18, h: mastH, fixed: true)
        let armW = q(double(200...240))
        let arm = b.rect("arm", .steel, x: mastX + armW / 2 - 9, bottom: Self.top(mast) - 16, w: armW, h: 16, fixed: true)
        let beamW = q(double(150...200)), beamBottom = b.floor + q(double(100...140))
        let beamX = q(arm.position.x + double(-10...10))
        let beam = b.rect("beam", crane ? .steel : .wood, x: beamX, bottom: beamBottom, w: beamW, h: 16)
        let ropeIds = ["rope1", "rope2"]
        for (i, side) in [-1.0, 1.0].enumerated() {
            let ax = side * (beamW / 2 - 10)
            let anchorArm = Vec2(beamX + ax - arm.position.x, -8)
            let anchorBeam = Vec2(ax, 8)
            let length = (Vec2(beamX + ax, arm.position.y - 8) - Vec2(beamX + ax, beam.position.y + 8)).length
            b.joints.append(Joint(id: ropeIds[i], type: .rope, a: arm.id, b: beam.id, anchorA: anchorArm, anchorB: anchorBeam,
                                  length: length, removable: true))
        }
        let postX = q(beamX + double(-beamW / 4 ... beamW / 4))
        let post = b.rect("post", .wood, x: postX, bottom: b.floor, w: 20, h: beamBottom - b.floor)
        var loads: [String] = []
        for x in [beamX - beamW / 3, beamX + beamW / 3] where chance(0.8) {
            loads.append(b.rect("load", .stone, x: q(x), bottom: Self.top(beam), w: 30, h: 30).id)
        }
        if loads.isEmpty { loads.append(b.rect("load", .stone, x: beamX, bottom: Self.top(beam), w: 34, h: 34).id) }
        if chance(0.5) {
            return Goal(type: .removeTargetsKeepStanding, targetPieceIds: ropeIds + [post.id], requiredCount: 2, moveBudget: 0, starThresholds: [])
        }
        return Goal(type: .dropOnlyTarget, targetPieceIds: [loads[0]], moveBudget: 0, starThresholds: [])
    }

    /// Stepped stone pyramid with shims and a keystone on top.
    private func pyramid(_ b: inout Builder) -> Goal {
        let tiers = int(2...3)
        var bottom = b.floor
        var width = q(double(200...260))
        var removable: [String] = []
        for t in 0..<tiers {
            let h = q(double(30...44))
            let n = t == 0 ? int(2...3) : 2
            let w = (width - Double(n - 1) * q(double(10...30))) / Double(n)
            for i in 0..<n {
                let x = -width / 2 + w / 2 + (width - w) * Double(i) / Double(max(1, n - 1))
                let fixed = t == 0 && chance(0.4)
                let p = b.rect("block", .stone, x: q(x), bottom: bottom, w: q(w), h: h, fixed: fixed)
                if p.removable { removable.append(p.id) }
            }
            bottom += h
            let shim = b.rect("shim", .wood, x: q(double(-10...10)), bottom: bottom, w: width - q(double(10...30)), h: 12)
            removable.append(shim.id)
            bottom = Self.top(shim)
            width *= 0.66
        }
        b.keystone(x: q(double(-12...12)), bottom: bottom, w: q(double(56...80)), h: q(double(36...46)))
        if chance(0.5) {
            return Goal(type: .dropOnlyTarget, targetPieceIds: ["k"], moveBudget: 0, starThresholds: [])
        }
        return Goal(type: .removeTargetsKeepStanding, targetPieceIds: removable, requiredCount: min(3, max(1, removable.count - 2)),
                    moveBudget: 0, starThresholds: [])
    }
}

extension Level {
    /// After solving: budget = shortest solution + slack, stars from the solution, annotation trimmed to the budget.
    public func tightened(slack: Int) -> Level {
        guard let a = annotation else { return self }
        var l = self
        let len = a.solutionPath.count
        let budget = min(goal.moveBudget, len + slack)
        l.goal.moveBudget = budget
        l.goal.starThresholds = [len, min(len + 1, budget), budget]
        var trimmed = a
        trimmed.stateMoves = a.stateMoves.filter { StateKey.tokens($0.state).count < budget }
        l.annotation = trimmed
        return l
    }
}
