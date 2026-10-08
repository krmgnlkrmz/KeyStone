import BalanceCore
import CoreGraphics
import SpriteKit

/// Tracks how far each watched body strays from its design pose during one evaluation window.
/// The decision itself is `SettleRules.verdict` (BalanceCore), shared with tests and the solver.
@MainActor
public final class SettleEvaluator {
    public let ids: [String]
    private let design: [Pose]
    private var peakT: [Double]
    private var peakR: [Double]
    private weak var structure: BuiltStructure?
    public let dropTargets: Set<String>
    public private(set) var firstCollapseTime: Double?
    public private(set) var samples = 0

    public init(structure: BuiltStructure, dropTargets: Set<String>) {
        self.structure = structure
        self.dropTargets = dropTargets
        ids = structure.monitoredIds
        design = ids.map { structure.designPoses[$0] ?? Pose(x: 0, y: 0, rotation: 0) }
        peakT = Array(repeating: 0, count: ids.count)
        peakR = Array(repeating: 0, count: ids.count)
    }

    /// Reads every watched body once. `time` is physics time since the window opened.
    public func sample(time: Double) {
        guard let structure else { return }
        samples += 1
        var collapsedNow = false
        for (i, id) in ids.enumerated() {
            guard let pose = structure.pose(id) else {
                // Body left the scene (shouldn't happen for watched bodies) — treat as fallen.
                peakT[i] = .infinity
                if !dropTargets.contains(id) { collapsedNow = true }
                continue
            }
            peakT[i] = max(peakT[i], pose.translation(from: design[i]))
            peakR[i] = max(peakR[i], pose.rotationDelta(from: design[i]))
            if !dropTargets.contains(id),
               peakT[i] >= PhysicsConstants.collapseTranslation || peakR[i] >= PhysicsConstants.collapseRotation {
                collapsedNow = true
            }
        }
        if collapsedNow && firstCollapseTime == nil { firstCollapseTime = time }
    }

    public var hasCollapsed: Bool { firstCollapseTime != nil }

    public func metrics() -> [BodyMetrics] {
        ids.enumerated().map { i, id in
            let body = structure?.node(id)?.physicsBody
            let v = body?.velocity ?? .zero
            let pose = structure?.pose(id)
            return BodyMetrics(
                id: id,
                peakTranslation: peakT[i],
                peakRotation: peakR[i],
                finalSpeed: Double(hypot(v.dx, v.dy)),
                finalAngularSpeed: Double(abs(body?.angularVelocity ?? 0)),
                finalDY: (pose?.y ?? -10_000) - design[i].y
            )
        }
    }

    public var allResting: Bool { metrics().allSatisfy(\.isResting) }

    public func verdict() -> SettleVerdict {
        SettleRules.verdict(metrics: metrics(), dropTargets: dropTargets)
    }
}
