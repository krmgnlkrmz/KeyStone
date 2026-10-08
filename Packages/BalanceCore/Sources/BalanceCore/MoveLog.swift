import Foundation

/// One player action. Undo never restores a snapshot: it drops the last move and replays the rest.
public struct Move: Codable, Sendable, Equatable, Hashable {
    public enum Kind: Codable, Sendable, Equatable, Hashable {
        /// Removes a piece, or cuts a removable rope (joint id).
        case remove(pieceId: String)
        /// Places a support strut. `position` is the strut's foot on the floor, x snapped to `supportGrid`.
        case placeSupport(position: Vec2, rotation: Double)
    }

    public let kind: Kind
    public let index: Int

    public init(kind: Kind, index: Int) {
        self.kind = kind
        self.index = index
    }

    /// Stable text form used by annotations and state keys: a piece id, or `+sup@<x>` / `+sup@<x>r<deg>`.
    public var token: String { kind.token }
}

extension Move.Kind {
    public var token: String {
        switch self {
        case let .remove(pieceId):
            return pieceId
        case let .placeSupport(position, rotation):
            return SupportToken.make(x: position.x, rotation: rotation)
        }
    }
}

public enum SupportToken {
    public static let prefix = "+sup@"

    public static func make(x: Double, rotation: Double) -> String {
        let xi = Int((x).rounded())
        let deg = Int((rotation * 180 / .pi).rounded())
        return deg == 0 ? "\(prefix)\(xi)" : "\(prefix)\(xi)r\(deg)"
    }

    public static func isSupport(_ token: String) -> Bool { token.hasPrefix(prefix) }

    /// Parses `+sup@-40` or `+sup@-40r15` into (x, rotation radians).
    public static func parse(_ token: String) -> (x: Double, rotation: Double)? {
        guard token.hasPrefix(prefix) else { return nil }
        let body = token.dropFirst(prefix.count)
        let parts = body.split(separator: "r", maxSplits: 1)
        guard let first = parts.first, let x = Double(first) else { return nil }
        var rotation = 0.0
        if parts.count == 2 {
            guard let deg = Double(parts[1]) else { return nil }
            rotation = deg * .pi / 180
        }
        return (x, rotation)
    }
}

/// The ordered list of moves made on a level. Equal logs describe equal states by definition.
public struct MoveLog: Codable, Sendable, Equatable {
    public private(set) var moves: [Move]

    public init(moves: [Move] = []) { self.moves = moves }

    public var count: Int { moves.count }
    public var isEmpty: Bool { moves.isEmpty }
    public var last: Move? { moves.last }

    @discardableResult
    public mutating func append(_ kind: Move.Kind) -> Move {
        let move = Move(kind: kind, index: moves.count)
        moves.append(move)
        return move
    }

    /// Drops the last move and returns it. The caller rebuilds the scene and replays `moves`.
    @discardableResult
    public mutating func undo() -> Move? {
        moves.popLast()
    }

    /// Keeps the first `n` moves.
    public mutating func truncate(to n: Int) {
        moves = Array(moves.prefix(max(0, n)))
    }

    public func truncated(to n: Int) -> MoveLog {
        var copy = self
        copy.truncate(to: n)
        return copy
    }

    public mutating func reset() { moves.removeAll() }

    /// Ids of removed pieces and cut ropes.
    public var removedIds: Set<String> {
        var out = Set<String>()
        for m in moves { if case let .remove(id) = m.kind { out.insert(id) } }
        return out
    }

    public var supportMoves: [(position: Vec2, rotation: Double)] {
        moves.compactMap {
            if case let .placeSupport(p, r) = $0.kind { return (p, r) }
            return nil
        }
    }

    public var supportsPlaced: Int { supportMoves.count }

    /// Order-independent key matching `StateMoves.state`.
    public var stateKey: String { StateKey.make(moves.map(\.token)) }
}

public enum StateKey {
    public static func make<S: Sequence>(_ tokens: S) -> String where S.Element == String {
        tokens.sorted().joined(separator: ",")
    }

    public static func tokens(_ key: String) -> [String] {
        key.isEmpty ? [] : key.split(separator: ",").map(String.init)
    }

    public static func adding(_ token: String, to key: String) -> String {
        make(tokens(key) + [token])
    }
}
