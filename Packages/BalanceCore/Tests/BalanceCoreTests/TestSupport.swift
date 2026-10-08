import Foundation
@testable import BalanceCore

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func level(_ name: String) throws -> Level {
        try Level.decode(from: data(name))
    }
}

func rectPiece(_ id: String, _ m: Material = .wood, x: Double, y: Double, w: Double, h: Double,
               fixed: Bool = false, removable: Bool = true) -> Piece {
    Piece(id: id, material: m, shape: .rect(w: w, h: h), position: Vec2(x, y), fixed: fixed, removable: removable)
}

/// Two posts under a beam with a block on top; floor at -100.
func bridgeLevel(annotation: Annotation? = nil) -> Level {
    Level(id: "t-bridge", pack: .curated, region: Region.woodScaffold.rawValue, index: 99, floorY: -100,
          goal: Goal(type: .removeTargetsKeepStanding, targetPieceIds: ["l", "r"], requiredCount: 1, moveBudget: 3, starThresholds: [1, 2, 3]),
          supportsAllowed: 1,
          pieces: [
            rectPiece("l", x: -80, y: -60, w: 20, h: 80),
            rectPiece("r", x: 80, y: -60, w: 20, h: 80),
            rectPiece("beam", x: 0, y: -10, w: 200, h: 20),
            rectPiece("load", .stone, x: 0, y: 15, w: 40, h: 30),
          ],
          annotation: annotation)
}
