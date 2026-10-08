import Foundation

/// A rigid-body pose in design points / radians.
public struct Pose: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var rotation: Double

    public init(x: Double, y: Double, rotation: Double) {
        self.x = x; self.y = y; self.rotation = rotation
    }

    public init(_ position: Vec2, _ rotation: Double) {
        x = position.x; y = position.y; self.rotation = rotation
    }

    public var position: Vec2 { Vec2(x, y) }

    public func translation(from o: Pose) -> Double { (position - o.position).length }

    /// Smallest absolute angle between the two rotations.
    public func rotationDelta(from o: Pose) -> Double {
        var d = (rotation - o.rotation).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return abs(d)
    }
}

/// What the evaluator measured for one monitored body during a settle window.
public struct BodyMetrics: Sendable, Hashable {
    public var id: String
    /// Largest distance from the design pose seen during the window.
    public var peakTranslation: Double
    /// Largest rotation away from the design pose seen during the window.
    public var peakRotation: Double
    public var finalSpeed: Double
    public var finalAngularSpeed: Double
    /// Vertical offset from the design pose at the end of the window (negative = lower).
    public var finalDY: Double

    public init(id: String, peakTranslation: Double, peakRotation: Double, finalSpeed: Double = 0,
                finalAngularSpeed: Double = 0, finalDY: Double = 0) {
        self.id = id; self.peakTranslation = peakTranslation; self.peakRotation = peakRotation
        self.finalSpeed = finalSpeed; self.finalAngularSpeed = finalAngularSpeed; self.finalDY = finalDY
    }

    /// Peak deviation as a fraction of the tolerance: ≥ 1 means this body collapsed.
    public var ratio: Double {
        max(peakTranslation / PhysicsConstants.collapseTranslation, peakRotation / PhysicsConstants.collapseRotation)
    }

    public var isResting: Bool {
        finalSpeed < PhysicsConstants.restingSpeed && finalAngularSpeed < PhysicsConstants.restingAngularSpeed
    }
}

public enum SettleOutcome: String, Codable, Sendable {
    /// Every watched body stayed within tolerance.
    case standing
    /// A watched body (other than a drop target) left its tolerance.
    case collapsed
    /// `dropOnlyTarget`: the target fell and nothing else moved past tolerance.
    case dropped
}

public struct SettleVerdict: Sendable, Hashable {
    public var outcome: SettleOutcome
    /// Worst ratio among the bodies that must stay up.
    public var worstRatio: Double
    /// Body with the worst ratio.
    public var worstBodyId: String?
    /// How far the decision is from flipping. ≥ `requiredMarginRatio` to ship.
    public var margin: Double
}

public enum SettleRules {
    /// - Parameters:
    ///   - metrics: monitored bodies still in the scene.
    ///   - dropTargets: ids that are allowed (and expected) to fall in a `dropOnlyTarget` level.
    ///   - missingTargets: drop targets no longer in the scene (fell off-world) count as dropped.
    public static func verdict(metrics: [BodyMetrics], dropTargets: Set<String> = [], missingTargets: Set<String> = []) -> SettleVerdict {
        var worst = 0.0
        var worstId: String?
        for m in metrics where !dropTargets.contains(m.id) {
            if m.ratio > worst { worst = m.ratio; worstId = m.id }
        }
        if worst >= 1 {
            return SettleVerdict(outcome: .collapsed, worstRatio: worst, worstBodyId: worstId, margin: worst)
        }
        let standingMargin = worst > 0 ? 1 / worst : .infinity
        if !dropTargets.isEmpty {
            var dropMargin = Double.infinity
            var allDropped = true
            for t in dropTargets {
                if missingTargets.contains(t) { continue }
                guard let m = metrics.first(where: { $0.id == t }) else { continue }
                let fall = -m.finalDY / PhysicsConstants.dropDistance
                if fall >= 1 { dropMargin = min(dropMargin, fall) } else { allDropped = false; dropMargin = min(dropMargin, fall > 0 ? 1 / fall : .infinity) }
            }
            if allDropped {
                return SettleVerdict(outcome: .dropped, worstRatio: worst, worstBodyId: worstId, margin: min(standingMargin, dropMargin))
            }
            return SettleVerdict(outcome: .standing, worstRatio: worst, worstBodyId: worstId, margin: min(standingMargin, dropMargin))
        }
        return SettleVerdict(outcome: .standing, worstRatio: worst, worstBodyId: worstId, margin: standingMargin)
    }
}

// MARK: - Goal

public enum MoveResult: String, Codable, Sendable {
    /// Goal met and the structure is standing (or only the target dropped).
    case won
    /// Something fell that should not have.
    case collapsed
    /// Still standing, goal not met, moves left.
    case continuePlaying
    /// Still standing, goal not met, budget spent.
    case outOfMoves
}

public enum GoalRules {
    public static func removedTargetCount(goal: Goal, removed: Set<String>) -> Int {
        goal.targetPieceIds.filter(removed.contains).count
    }

    /// For remove goals: enough targets removed (and a support placed when required).
    public static func removalSatisfied(goal: Goal, removed: Set<String>, supportsPlaced: Int) -> Bool {
        switch goal.type {
        case .dropOnlyTarget:
            return false
        case .removeTargetsKeepStanding:
            return removedTargetCount(goal: goal, removed: removed) >= goal.effectiveRequiredCount
        case .placeSupportThenRemove:
            return supportsPlaced >= 1 && removedTargetCount(goal: goal, removed: removed) >= goal.effectiveRequiredCount
        }
    }

    public static func result(goal: Goal, removed: Set<String>, supportsPlaced: Int, movesMade: Int, outcome: SettleOutcome) -> MoveResult {
        switch outcome {
        case .collapsed:
            return .collapsed
        case .dropped:
            return goal.type == .dropOnlyTarget ? .won : .collapsed
        case .standing:
            if removalSatisfied(goal: goal, removed: removed, supportsPlaced: supportsPlaced) { return .won }
            return movesMade >= goal.moveBudget ? .outOfMoves : .continuePlaying
        }
    }
}

// MARK: - Blame

/// Picks the piece to blame when a recorded collapse has no offline annotation (§4.4 step 2).
public enum CulpritHeuristic {
    /// - Parameters:
    ///   - frames: poses per recorded step, starting at the move.
    ///   - collapseFrame: first frame where a body crossed its tolerance.
    ///   - bounds: design-pose bounds per body (used for "below" and "nearest").
    ///   - candidates: bodies that may be blamed (monitored, still present).
    public static func culprit(frames: [[String: Pose]], collapseFrame: Int, bounds: [String: Rect2],
                               candidates: Set<String>, window: Int = 30) -> String? {
        guard !frames.isEmpty else { return nil }
        let start = min(max(0, collapseFrame), frames.count - 1)
        let end = min(frames.count - 1, start + window)
        let first = frames[start]

        var spinner: String?
        var bestSpin = 0.0
        for id in candidates.sorted() {
            guard let p0 = first[id] else { continue }
            var spin = 0.0
            for f in start...end { if let p = frames[f][id] { spin = max(spin, p.rotationDelta(from: p0)) } }
            if spin > bestSpin { bestSpin = spin; spinner = id }
        }
        guard let rotating = spinner, let rb = bounds[rotating], let pose = first[rotating] else { return nil }

        // Nearest body below the rotating body's centre of mass at t0, overlapping it horizontally.
        var best: (id: String, gap: Double)?
        for id in candidates.sorted() where id != rotating {
            guard let b = bounds[id], let p = first[id] else { continue }
            let halfH = b.height / 2
            let top = p.y + halfH
            guard top <= pose.y + 0.5 else { continue }
            let halfW = b.width / 2
            let overlap = min(p.x + halfW, pose.x + rb.width / 2) - max(p.x - halfW, pose.x - rb.width / 2)
            guard overlap > -4 else { continue }
            let gap = (pose.y - rb.height / 2) - top
            let distance = abs(gap) + max(0, -overlap)
            if best == nil || distance < best!.gap { best = (id, distance) }
        }
        return best?.id ?? rotating
    }
}

// MARK: - Piece naming (callouts, VoiceOver)

public enum PieceNoun: String, Sendable, CaseIterable {
    case post, beam, block, column, girder, keystone, support, rope, piece
}

public enum PieceNaming {
    public static func noun(for piece: Piece) -> PieceNoun {
        if SupportToken.isSupport(piece.id) { return .support }
        let (w, h) = piece.shape.size
        let c = abs(cos(piece.rotation)), s = abs(sin(piece.rotation))
        let ww = w * c + h * s, hh = w * s + h * c
        switch piece.material {
        case .brass: return .keystone
        case .rope: return .rope
        case .stone: return .block
        case .steel: return hh > ww * 1.3 ? .column : .girder
        case .wood:
            if hh > ww * 1.3 { return .post }
            if ww > hh * 1.3 { return .beam }
            return .block
        }
    }
}
