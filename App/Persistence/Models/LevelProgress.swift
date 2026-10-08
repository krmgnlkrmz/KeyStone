import Foundation
import SwiftData

@Model
final class LevelProgress {
    @Attribute(.unique) var levelId: String
    var bestMoves: Int?
    /// 0…3
    var stars: Int = 0
    var completedAt: Date?
    var attempts: Int = 0
    var usedHint: Bool = false

    init(levelId: String) {
        self.levelId = levelId
    }
}
