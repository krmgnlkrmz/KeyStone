import Foundation

/// The single source of truth for every physics number.
///
/// The game scene (`StructureSceneBuilder`/`GameScene`), the headless simulator and the solver all read
/// from here. Level files never carry physics numbers; they name a `Material`.
///
/// Changing anything in this file changes `fingerprint`, which makes every shipped level's annotation
/// stale until LevelForge re-verifies it (`make forge-validate`).
public enum PhysicsConstants {
    /// Bump when SpriteKit's solver behaviour is known to change between OS releases.
    public static let engineFamily = "spk-1"

    public static let gravityDY: Double = -9.8
    public static let stepHz: Int = 60
    public static var stepDuration: Double { 1.0 / Double(stepHz) }

    /// After a move the structure is evaluated over this window.
    public static let settleWindow: Double = 2.0
    /// Hard cap on one evaluation, including the replay tail after a collapse.
    public static let maxSimSeconds: Double = 4.0
    /// Silent settle when a level is first built (no evaluation, input locked).
    public static let initialSettle: Double = 0.5
    /// Recording continues this long after a collapse is detected, so the replay shows the fall.
    public static let collapseTail: Double = 1.6

    // Collapse tolerances (design points / radians), measured against the design pose.
    public static let collapseTranslation: Double = 26.0
    public static let collapseRotation: Double = 0.30
    public static let restingSpeed: Double = 6.0
    public static let restingAngularSpeed: Double = 0.12

    /// A `dropOnlyTarget` target counts as dropped once its centre is this far below its design pose.
    public static let dropDistance: Double = 40.0

    /// A shipped level must keep every decision this far from the threshold (§4.2 rule 4).
    public static let requiredMarginRatio: Double = 1.4
    /// Severity (peak / tolerance) splitting tense from critical.
    public static let criticalSeverity: Double = 2.0
    /// Safe moves below this severity show no tension mark at all.
    public static let lightSeverityFloor: Double = 0.25

    /// Thin beams get continuous collision detection.
    public static let preciseCollisionMaxThickness: Double = 16.0

    // Support strut (placeSupportThenRemove).
    public static let supportWidth: Double = 14.0
    public static let supportMinHeight: Double = 24.0
    public static let supportGrid: Double = 8.0
    /// Angles (radians) the solver tries for a support. Upright only in v1; see docs/physics-notes.md.
    public static let supportAngles: [Double] = [0]
    public static let supportMaterial: Material = .steel

    /// Floor body that catches falling pieces.
    public static let floorFriction: Double = 0.9

    public struct MaterialSpec: Sendable, Hashable {
        public let density: Double
        public let friction: Double
        public let restitution: Double
        public let linearDamping: Double
        public let angularDamping: Double
    }

    public static func spec(for material: Material) -> MaterialSpec {
        switch material {
        case .wood: return MaterialSpec(density: 0.6, friction: 0.75, restitution: 0.02, linearDamping: 0.35, angularDamping: 0.8)
        case .stone: return MaterialSpec(density: 2.0, friction: 0.9, restitution: 0.0, linearDamping: 0.35, angularDamping: 0.8)
        case .steel: return MaterialSpec(density: 1.4, friction: 0.6, restitution: 0.05, linearDamping: 0.3, angularDamping: 0.7)
        case .brass: return MaterialSpec(density: 1.6, friction: 0.7, restitution: 0.02, linearDamping: 0.35, angularDamping: 0.8)
        case .rope: return MaterialSpec(density: 0.3, friction: 0.8, restitution: 0.0, linearDamping: 0.5, angularDamping: 1.0)
        }
    }

    /// Canonical text of every constant that affects simulation results.
    public static var canonicalDescription: String {
        var parts: [String] = [
            engineFamily, "g=\(gravityDY)", "hz=\(stepHz)", "win=\(settleWindow)", "max=\(maxSimSeconds)",
            "init=\(initialSettle)", "tr=\(collapseTranslation)", "rot=\(collapseRotation)", "rs=\(restingSpeed)",
            "ras=\(restingAngularSpeed)", "drop=\(dropDistance)", "thin=\(preciseCollisionMaxThickness)",
            "sw=\(supportWidth)", "sh=\(supportMinHeight)", "sg=\(supportGrid)", "sa=\(supportAngles)",
            "smat=\(supportMaterial.rawValue)", "ff=\(floorFriction)",
        ]
        for m in Material.allCases {
            let s = spec(for: m)
            parts.append("\(m.rawValue)=\(s.density),\(s.friction),\(s.restitution),\(s.linearDamping),\(s.angularDamping)")
        }
        return parts.joined(separator: "|")
    }

    /// Short stable hash of the constants, e.g. `spk-1-60hz-c9f1`.
    public static var fingerprint: String {
        let hash = StableHash.fnv1a64(canonicalDescription)
        let short = String(hash & 0xFFFF, radix: 16)
        return "\(engineFamily)-\(stepHz)hz-\(String(repeating: "0", count: 4 - short.count))\(short)"
    }
}

/// Deterministic, platform-independent hashing (Swift's `Hasher` is seeded per process).
public enum StableHash {
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
