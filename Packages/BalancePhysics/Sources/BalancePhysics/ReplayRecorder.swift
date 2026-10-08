import BalanceCore
import Foundation

/// A frozen collapse: transforms per frame, played back with physics off.
/// Playing it twice shows exactly the same thing — nothing is re-simulated.
public struct Recording: Sendable, Equatable {
    public var levelId: String
    /// Bodies in the recording, in structure order.
    public var ids: [String]
    /// Physics time of each frame since the move.
    public var times: [Double]
    /// `frames[i][j]` is the pose of `ids[j]` at `times[i]`.
    public var frames: [[Pose]]
    /// Pieces taken away by the move, at their pose when removed (drawn as a dashed origin).
    public var removedOrigins: [String: Pose]
    public var collapseTime: Double?
    public var culprit: String?
    /// 1-based move number that triggered the collapse.
    public var moveNumber: Int

    public init(levelId: String, ids: [String], times: [Double], frames: [[Pose]], removedOrigins: [String: Pose],
                collapseTime: Double?, culprit: String?, moveNumber: Int) {
        self.levelId = levelId; self.ids = ids; self.times = times; self.frames = frames
        self.removedOrigins = removedOrigins; self.collapseTime = collapseTime; self.culprit = culprit
        self.moveNumber = moveNumber
    }

    public var duration: Double { times.last ?? 0 }
    public var isEmpty: Bool { frames.isEmpty }

    /// Index of the last frame at or before `time`.
    public func frameIndex(at time: Double) -> Int {
        guard !times.isEmpty else { return 0 }
        var lo = 0, hi = times.count - 1
        if time <= times[0] { return 0 }
        if time >= times[hi] { return hi }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if times[mid] <= time { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Linearly interpolated poses at `time` (rotation interpolated along the short arc).
    public func poses(at time: Double) -> [String: Pose] {
        guard !frames.isEmpty else { return [:] }
        let i = frameIndex(at: time)
        let j = min(i + 1, frames.count - 1)
        let span = times[j] - times[i]
        let u = span > 0 ? min(1, max(0, (time - times[i]) / span)) : 0
        var out: [String: Pose] = [:]
        for (k, id) in ids.enumerated() {
            let a = frames[i][k], b = frames[j][k]
            var dr = b.rotation - a.rotation
            while dr > .pi { dr -= 2 * .pi }
            while dr < -.pi { dr += 2 * .pi }
            out[id] = Pose(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u, rotation: a.rotation + dr * u)
        }
        return out
    }

    /// The frames as `[id: Pose]` dictionaries, for `CulpritHeuristic`.
    public var keyedFrames: [[String: Pose]] {
        frames.map { row in Dictionary(uniqueKeysWithValues: zip(ids, row)) }
    }

    public func firstFrame(atOrAfter time: Double) -> Int {
        times.firstIndex { $0 >= time } ?? max(0, times.count - 1)
    }
}

/// Ring buffer of transforms, written every simulated frame while a move is evaluated.
@MainActor
public final class ReplayRecorder {
    public static let capacity = Int(PhysicsConstants.maxSimSeconds * 120) + 32

    private var ids: [String] = []
    private var times: [Double] = []
    private var frames: [[Pose]] = []
    private var removedOrigins: [String: Pose] = [:]

    public init() {}

    public func begin(ids: [String], removedOrigins: [String: Pose]) {
        self.ids = ids
        self.removedOrigins = removedOrigins
        times.removeAll(keepingCapacity: true)
        frames.removeAll(keepingCapacity: true)
    }

    public func record(time: Double, structure: BuiltStructure) {
        guard !ids.isEmpty else { return }
        var row: [Pose] = []
        row.reserveCapacity(ids.count)
        for id in ids {
            row.append(structure.pose(id) ?? structure.designPoses[id] ?? Pose(x: 0, y: -10_000, rotation: 0))
        }
        if frames.count >= Self.capacity {
            frames.removeFirst()
            times.removeFirst()
        }
        times.append(time)
        frames.append(row)
    }

    public var frameCount: Int { frames.count }

    public func freeze(levelId: String, collapseTime: Double?, culprit: String?, moveNumber: Int) -> Recording {
        Recording(levelId: levelId, ids: ids, times: times, frames: frames, removedOrigins: removedOrigins,
                  collapseTime: collapseTime, culprit: culprit, moveNumber: moveNumber)
    }
}
