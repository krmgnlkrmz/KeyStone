import Foundation

/// Three-tier load hint shown on pieces. It implies, it doesn't tell (§4.5).
public enum TensionTier: Int, Codable, Sendable, Comparable, CaseIterable {
    case none = 0
    case light = 1
    case tense = 2
    case critical = 3

    public static func < (a: TensionTier, b: TensionTier) -> Bool { a.rawValue < b.rawValue }
}

/// Read-only view over a level's offline annotation: tension tiers, blame and hints.
///
/// If the annotation was produced with different physics constants (fingerprint mismatch) the index
/// reports `isUsable == false`; the game then hides tension marks and hints but stays playable.
public struct TensionIndex: Sendable {
    public let isUsable: Bool
    public let mismatchReason: String?
    public let solutionPath: [String]
    private let states: [String: StateMoves]

    public init(level: Level, runtimeFingerprint: String = PhysicsConstants.fingerprint) {
        guard let a = level.annotation else {
            isUsable = false; mismatchReason = "no annotation"; solutionPath = []; states = [:]
            return
        }
        guard a.engineFingerprint == runtimeFingerprint else {
            isUsable = false
            mismatchReason = "fingerprint \(a.engineFingerprint) ≠ runtime \(runtimeFingerprint)"
            solutionPath = []; states = [:]
            return
        }
        isUsable = true
        mismatchReason = nil
        solutionPath = a.solutionPath
        var map: [String: StateMoves] = [:]
        for s in a.stateMoves { map[StateKey.make(StateKey.tokens(s.state))] = s }
        states = map
    }

    public var stateCount: Int { states.count }

    public func entry(for stateKey: String) -> StateMoves? { states[stateKey] }

    /// Tier for each removable id still in play. Unknown states give no marks.
    /// - Parameter revealCritical: false until the player took a hint on this attempt; critical shows as tense.
    public func tiers(stateKey: String, revealCritical: Bool) -> [String: TensionTier] {
        guard isUsable, let e = states[stateKey] else { return [:] }
        var out: [String: TensionTier] = [:]
        for id in e.safe where !SupportToken.isSupport(id) {
            let sev = e.severity?[id] ?? 0.5
            out[id] = sev < PhysicsConstants.lightSeverityFloor ? TensionTier.none : .light
        }
        for (id, _) in e.unsafeMoves where !SupportToken.isSupport(id) {
            let sev = e.severity?[id] ?? 1.5
            let tier: TensionTier = sev >= PhysicsConstants.criticalSeverity ? .critical : .tense
            out[id] = (tier == .critical && !revealCritical) ? .tense : tier
        }
        for id in e.win ?? [] where out[id] == nil && !SupportToken.isSupport(id) {
            out[id] = .light
        }
        return out
    }

    /// The piece that gave way when `move` was made from `stateKey`, if the solver recorded it.
    public func culprit(stateKey: String, move: String) -> String? {
        guard isUsable else { return nil }
        return states[stateKey]?.unsafeMoves[move]
    }

    /// First move of a shortest known path from `stateKey` to the goal within `movesLeft` moves.
    /// Prefers the shipped solution path when the player is on it.
    public func hint(stateKey: String, movesLeft: Int) -> String? {
        guard isUsable, movesLeft > 0, states[stateKey] != nil else { return nil }
        // On the solution path? Then its next step is a shortest continuation.
        let done = StateKey.tokens(stateKey)
        if done.count < solutionPath.count, StateKey.make(solutionPath.prefix(done.count)) == stateKey,
           solutionPath.count - done.count <= movesLeft {
            return solutionPath[done.count]
        }
        // Breadth-first over recorded safe transitions.
        var frontier: [(key: String, first: String?)] = [(stateKey, nil)]
        var seen: Set<String> = [stateKey]
        for _ in 0..<movesLeft {
            var next: [(key: String, first: String?)] = []
            for node in frontier {
                guard let e = states[node.key] else { continue }
                if let win = e.win?.sorted().first { return node.first ?? win }
                for move in e.safe.sorted() {
                    let child = StateKey.adding(move, to: node.key)
                    guard seen.insert(child).inserted else { continue }
                    next.append((child, node.first ?? move))
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        return nil
    }

    /// True when the solver proved no solution exists from this state within the budget
    /// (the state is known but no path reaches the goal).
    public func isDeadEnd(stateKey: String, movesLeft: Int) -> Bool {
        isUsable && states[stateKey] != nil && hint(stateKey: stateKey, movesLeft: movesLeft) == nil
    }
}
