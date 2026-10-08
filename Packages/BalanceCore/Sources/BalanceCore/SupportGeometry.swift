import Foundation

/// Where an upright support strut can stand, computed from the design pose.
///
/// The solver and the game share this function, so a strut the player drops always snaps to a position
/// the solver explored, and its state key matches the annotation.
public struct SupportPlacement: Codable, Sendable, Hashable {
    /// Strut centre x, snapped to `PhysicsConstants.supportGrid`.
    public var x: Double
    /// Foot of the strut (the floor).
    public var bottomY: Double
    /// Top of the strut (underside of the supported piece).
    public var topY: Double
    public var width: Double
    public var rotation: Double
    /// The piece the strut pushes against.
    public var targetId: String?
    public var isValid: Bool

    public var height: Double { topY - bottomY }
    public var center: Vec2 { Vec2(x, (topY + bottomY) / 2) }
    public var token: String { SupportToken.make(x: x, rotation: rotation) }
    public var footPosition: Vec2 { Vec2(x, bottomY) }

    public var asPiece: Piece {
        Piece(id: token, material: PhysicsConstants.supportMaterial,
              shape: .rect(w: width, h: max(1, height)), position: center, rotation: rotation,
              fixed: false, removable: false, monitored: true)
    }
}

public enum SupportGeometry {
    public static func snap(_ x: Double) -> Double {
        let g = PhysicsConstants.supportGrid
        return (x / g).rounded() * g
    }

    /// Pieces present in the state: level pieces minus removed ones, plus struts already placed.
    public static func presentPieces(level: Level, removed: Set<String>, supports: [SupportPlacement]) -> [Piece] {
        level.pieces.filter { !removed.contains($0.id) } + supports.map(\.asPiece)
    }

    /// Placement for a strut centred at `x` (snapped). Invalid placements still return geometry for the ghost.
    public static func placement(atX rawX: Double, level: Level, removed: Set<String>,
                                 supports: [SupportPlacement] = []) -> SupportPlacement {
        let x = snap(rawX)
        let w = PhysicsConstants.supportWidth
        let floor = level.resolvedFloorY
        let x0 = x - w / 2, x1 = x + w / 2
        let pieces = presentPieces(level: level, removed: removed, supports: supports)

        var best: (piece: Piece, underside: Double)?
        for p in pieces {
            let b = p.worldBounds
            guard b.maxX > x0 + 0.5, b.minX < x1 - 0.5 else { continue }
            let underside = undersideY(of: p, from: x0, to: x1) ?? b.minY
            if best == nil || underside < best!.underside { best = (p, underside) }
        }

        guard let target = best else {
            return SupportPlacement(x: x, bottomY: floor, topY: floor + 60, width: w, rotation: 0, targetId: nil, isValid: false)
        }
        let b = target.piece.worldBounds
        let fitsUnder = x0 >= b.minX - 0.01 && x1 <= b.maxX + 0.01
        let height = target.underside - floor
        let valid = fitsUnder && height >= PhysicsConstants.supportMinHeight && !SupportToken.isSupport(target.piece.id)
        return SupportPlacement(x: x, bottomY: floor, topY: max(floor + PhysicsConstants.supportMinHeight, target.underside),
                                width: w, rotation: 0, targetId: target.piece.id, isValid: valid)
    }

    /// The finite set of strut positions the solver explores and the game snaps to:
    /// three positions under each piece that has room beneath it (near each end and the middle).
    public static func candidates(level: Level, removed: Set<String>, supports: [SupportPlacement] = []) -> [SupportPlacement] {
        let w = PhysicsConstants.supportWidth
        var xs: [Double] = []
        for p in presentPieces(level: level, removed: removed, supports: supports) where !SupportToken.isSupport(p.id) {
            let b = p.worldBounds
            guard b.width >= w else { continue }
            for f in [0.15, 0.5, 0.85] {
                let raw = b.minX + w / 2 + (b.width - w) * f
                var sx = snap(raw)
                // Keep the snapped strut inside the piece's span.
                if sx - w / 2 < b.minX { sx += PhysicsConstants.supportGrid }
                if sx + w / 2 > b.maxX { sx -= PhysicsConstants.supportGrid }
                xs.append(sx)
            }
        }
        var seen = Set<Int>()
        var out: [SupportPlacement] = []
        for x in xs.sorted() where seen.insert(Int(x.rounded())).inserted {
            let pl = placement(atX: x, level: level, removed: removed, supports: supports)
            if pl.isValid { out.append(pl) }
        }
        return out
    }

    /// Nearest candidate within `radius`, used by the drag ghost to snap.
    public static func snapToCandidate(x: Double, candidates: [SupportPlacement], radius: Double = 40) -> SupportPlacement? {
        candidates.min { abs($0.x - x) < abs($1.x - x) }.flatMap { abs($0.x - x) <= radius ? $0 : nil }
    }

    /// Lowest point of the piece's outline over [x0, x1] (its underside directly above the strut).
    static func undersideY(of piece: Piece, from x0: Double, to x1: Double) -> Double? {
        let pts = piece.worldOutline
        var ys: [Double] = []
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            if a.x >= x0 && a.x <= x1 { ys.append(a.y) }
            for xv in [x0, x1] where (a.x - xv) * (b.x - xv) < 0 {
                let t = (xv - a.x) / (b.x - a.x)
                ys.append(a.y + (b.y - a.y) * t)
            }
        }
        return ys.min()
    }
}
