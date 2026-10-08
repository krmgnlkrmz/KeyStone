import BalanceCore
import Foundation

/// Searches removal orders with the headless simulator and produces a level's annotation.
///
/// - A state is the set of removed pieces (plus placed supports). An edge is "make move M from
///   state S": rebuild S from scratch, settle quietly, make M, run the evaluation window. This is
///   exactly what the game does after an undo, so annotation and play agree.
/// - Breadth-first over depth ≤ `moveBudget`, memoised by state key; the first goal found is a
///   shortest solution. Every explored state keeps its safe / unsafe / win neighbourhood so the game
///   can show tension and hints anywhere the player wanders, not only on the solution path.
/// - The solution path is then replayed under five frame-timing profiles; every decision must agree
///   and stay `requiredMarginRatio` away from its threshold, or the level is rejected.
@MainActor
public final class SolutionSolver {
    public struct Options: Sendable {
        public var maxStates: Int = 400
        public var verifyProfiles: [StepProfile] = StepProfile.validationSet
        public var requiredMargin: Double = PhysicsConstants.requiredMarginRatio
        public var rejectTooEasy: Bool = true
        /// Pool levels also need at least this many moves in the shortest solution.
        public var minimumSolutionLength: Int = 1
        public var collapseTail: Double = 0.6
        public init() {}
    }

    public enum Rejection: String, Sendable, Codable {
        case invalid, initialUnstable, unsolvable, tooEasy, tooShort, narrowMargin, inconsistent, simulationError
    }

    public struct Report: Sendable {
        public var levelId: String
        public var rejection: Rejection?
        public var detail: String
        public var annotatedLevel: Level?
        public var solutionLength: Int?
        public var marginRatio: Double?
        public var exploredStates: Int
        public var evaluations: Int
        public var seconds: Double
        /// [3★, 2★, 1★] bounds derived from the shortest solution.
        public var suggestedThresholds: [Int]?
        public var unsafeShare: Double
        /// Every explored state's neighbourhood, in BFS order (diagnostics for rejected levels).
        public var states: [StateMoves] = []

        public var accepted: Bool { rejection == nil }
    }

    private let sim: HeadlessSimulator
    public var options: Options
    public private(set) var evaluations = 0

    public init(simulator: HeadlessSimulator, options: Options = Options()) {
        self.sim = simulator
        self.options = options
    }

    private struct Node {
        var key: String
        var log: MoveLog
        var depth: Int
    }

    public func solve(_ input: Level, verifiedAt: String) -> Report {
        let started = Date()
        evaluations = 0
        var level = input
        level.annotation = nil
        var states: [String: StateMoves] = [:]
        var order: [String] = []
        func report(_ r: Rejection?, _ detail: String, explored: Int = 0, path: [String]? = nil, margin: Double? = nil,
                    annotated: Level? = nil, unsafeShare: Double = 0) -> Report {
            let len = path?.count
            return Report(levelId: level.id, rejection: r, detail: detail, annotatedLevel: annotated, solutionLength: len,
                          marginRatio: margin, exploredStates: explored, evaluations: evaluations,
                          seconds: Date().timeIntervalSince(started),
                          suggestedThresholds: len.map { [$0, min($0 + 1, level.goal.moveBudget), level.goal.moveBudget] },
                          unsafeShare: unsafeShare, states: order.compactMap { states[$0] })
        }

        let problems = level.validate()
        if !problems.isEmpty { return report(.invalid, problems.map(\.description).joined(separator: "; ")) }

        do {
            // 1. The untouched structure must stand, with margin, under every profile.
            var initialMargin = Double.infinity
            for profile in options.verifyProfiles {
                let r = try run(level, MoveLog(), nil, profile)
                guard r.verdict.outcome == .standing else {
                    return report(.initialUnstable, "\(profile): \(r.verdict.worstBodyId ?? "?") moved \(fmt(r.verdict.worstRatio))× tolerance")
                }
                initialMargin = min(initialMargin, r.verdict.margin)
            }
            if initialMargin < options.requiredMargin {
                return report(.initialUnstable, "initial margin \(fmt(initialMargin))")
            }

            // 2. Breadth-first over states.
            var parents: [String: (parent: String, move: String)] = [:]
            var queue: [Node] = [Node(key: "", log: MoveLog(), depth: 0)]
            var seen: Set<String> = [""]
            var head = 0
            var firstWin: (key: String, move: String)?
            var unsafeCount = 0, moveCount = 0

            while head < queue.count, states.count < options.maxStates {
                let node = queue[head]; head += 1
                guard node.depth < level.goal.moveBudget else { continue }
                var safe: [String] = [], win: [String] = []
                var unsafe: [String: String] = [:], severity: [String: Double] = [:]
                for kind in candidateMoves(level: level, log: node.log) {
                    let r = try run(level, node.log, kind, .standard)
                    let token = kind.token
                    severity[token] = (r.verdict.worstRatio * 1000).rounded() / 1000
                    moveCount += 1
                    switch r.moveResult {
                    case .won:
                        win.append(token)
                        if firstWin == nil { firstWin = (node.key, token) }
                    case .continuePlaying, .outOfMoves:
                        safe.append(token)
                        let child = StateKey.adding(token, to: node.key)
                        if seen.insert(child).inserted {
                            var log = node.log
                            log.append(kind)
                            queue.append(Node(key: child, log: log, depth: node.depth + 1))
                            parents[child] = (node.key, token)
                        }
                    case .collapsed:
                        unsafeCount += 1
                        unsafe[token] = r.heuristicCulprit ?? r.verdict.worstBodyId ?? token
                    }
                }
                states[node.key] = StateMoves(state: node.key, safe: safe, unsafe: unsafe, severity: severity,
                                              win: win.isEmpty ? nil : win)
                order.append(node.key)
            }
            let unsafeShare = moveCount > 0 ? Double(unsafeCount) / Double(moveCount) : 0

            guard let win = firstWin else {
                return report(.unsolvable, "no solution within \(level.goal.moveBudget) moves", explored: states.count, unsafeShare: unsafeShare)
            }
            var path = [win.move]
            var k = win.key
            while let p = parents[k] { path.insert(p.move, at: 0); k = p.parent }

            if options.rejectTooEasy, let root = states[""], root.unsafeMoves.isEmpty {
                return report(.tooEasy, "every first move is safe", explored: states.count, path: path, unsafeShare: unsafeShare)
            }
            if path.count < options.minimumSolutionLength {
                return report(.tooShort, "solution has \(path.count) moves", explored: states.count, path: path, unsafeShare: unsafeShare)
            }

            // 3. Replay the solution under every profile; decisions must agree, with margin.
            var margin = initialMargin
            for profile in options.verifyProfiles {
                var log = MoveLog()
                for (i, token) in path.enumerated() {
                    guard let kind = moveKind(token, level: level, log: log) else {
                        return report(.inconsistent, "cannot rebuild move \(token)", explored: states.count, path: path)
                    }
                    let r = try run(level, log, kind, profile)
                    let expected: MoveResult = i == path.count - 1 ? .won : .continuePlaying
                    let got = r.moveResult == .outOfMoves ? .continuePlaying : r.moveResult
                    guard got == expected else {
                        return report(.inconsistent, "\(profile) move \(i + 1) \(token): \(r.moveResult) ≠ \(expected)",
                                      explored: states.count, path: path, unsafeShare: unsafeShare)
                    }
                    margin = min(margin, r.verdict.margin)
                    log.append(kind)
                }
            }
            if margin < options.requiredMargin {
                return report(.narrowMargin, "margin \(fmt(margin)) < \(options.requiredMargin)", explored: states.count,
                              path: path, margin: margin, unsafeShare: unsafeShare)
            }

            let difficulty = (Double(path.count) * (0.5 + unsafeShare) * 100).rounded() / 100
            level.annotation = Annotation(solutionPath: path, stateMoves: order.compactMap { states[$0] },
                                          verifiedAt: verifiedAt, engineFingerprint: PhysicsConstants.fingerprint,
                                          marginRatio: (min(margin, 99) * 100).rounded() / 100, difficulty: difficulty)
            return report(nil, "ok", explored: states.count, path: path, margin: margin, annotated: level, unsafeShare: unsafeShare)
        } catch {
            return report(.simulationError, "\(error)")
        }
    }

    /// Moves available in a state, in a fixed order: pieces/ropes in file order, then strut positions left to right.
    public func candidateMoves(level: Level, log: MoveLog) -> [Move.Kind] {
        if log.count >= level.goal.moveBudget { return [] }
        let removed = log.removedIds
        var out: [Move.Kind] = level.removableIds.filter { !removed.contains($0) }.map { .remove(pieceId: $0) }
        if level.supportsAllowed > log.supportsPlaced {
            let placed = resolvedSupports(level: level, log: log)
            for c in SupportGeometry.candidates(level: level, removed: removed, supports: placed) {
                out.append(.placeSupport(position: c.footPosition, rotation: c.rotation))
            }
        }
        return out
    }

    private func resolvedSupports(level: Level, log: MoveLog) -> [SupportPlacement] {
        var removed = Set<String>()
        var supports: [SupportPlacement] = []
        for m in log.moves {
            switch m.kind {
            case let .remove(id): removed.insert(id)
            case let .placeSupport(pos, _):
                let p = SupportGeometry.placement(atX: pos.x, level: level, removed: removed, supports: supports)
                if p.isValid { supports.append(p) }
            }
        }
        return supports
    }

    private func moveKind(_ token: String, level: Level, log: MoveLog) -> Move.Kind? {
        if let s = SupportToken.parse(token) {
            let placed = resolvedSupports(level: level, log: log)
            let p = SupportGeometry.placement(atX: s.x, level: level, removed: log.removedIds, supports: placed)
            return p.isValid ? .placeSupport(position: p.footPosition, rotation: s.rotation) : nil
        }
        return .remove(pieceId: token)
    }

    private func run(_ level: Level, _ base: MoveLog, _ move: Move.Kind?, _ profile: StepProfile) throws -> EvaluationResult {
        evaluations += 1
        return try sim.run(.init(level: level, base: base, move: move, profile: profile, collapseTail: options.collapseTail))
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}
