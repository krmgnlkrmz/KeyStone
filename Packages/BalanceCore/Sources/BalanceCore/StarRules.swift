import Foundation

public enum StarRules {
    /// Stars for finishing a level in `moves` moves.
    ///
    /// `thresholds` are upper move bounds for 3, 2 and 1 stars. Files may list them in either order
    /// (`[5,6,7]` or `[7,6,5]`); the smallest bound always earns three stars. A finished level always
    /// earns at least one star, since the move budget already capped the attempt.
    public static func stars(moves: Int, thresholds: [Int]) -> Int {
        let t = normalize(thresholds, budget: nil)
        guard t.count == 3 else { return moves > 0 ? 1 : 0 }
        if moves <= t[0] { return 3 }
        if moves <= t[1] { return 2 }
        return 1
    }

    public static func stars(moves: Int, goal: Goal) -> Int {
        stars(moves: moves, thresholds: goal.normalizedThresholds)
    }

    /// Sorted ascending, clamped to the budget when one is given.
    public static func normalize(_ thresholds: [Int], budget: Int?) -> [Int] {
        var t = thresholds.sorted()
        if let budget { t = t.map { min($0, budget) } }
        return t
    }

    /// Moves needed for the next star, or nil at three stars.
    public static func movesForNextStar(currentStars: Int, thresholds: [Int]) -> Int? {
        let t = normalize(thresholds, budget: nil)
        guard t.count == 3, currentStars < 3 else { return nil }
        return t[max(0, 2 - currentStars)]
    }
}
