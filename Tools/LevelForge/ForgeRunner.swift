import BalanceCore
import BalancePhysics
import Foundation
import XCTest

/// Offline level production, dressed as XCTest so SpriteKit runs inside the iOS Simulator
/// with the same frameworks as the shipping game. See Tools/LevelForge/README.md.
///
/// Environment (pass through xcodebuild with the TEST_RUNNER_ prefix):
///   FORGE_OUT        output folder (default: <tmp>/forge)
///   FORGE_COUNT      pool candidates to try (testGeneratePool, default 1200)
///   FORGE_SEED_BASE  first generator seed (default 9000)
///   FORGE_SHARD      "i/n": only seeds with (seed % n == i), for parallel simulators
final class ForgeRunner: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private var outDir: URL {
        let path = env["FORGE_OUT"] ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("forge")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let today: String = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }()

    private func log(_ s: String) {
        print("[forge] \(s)")
    }

    private func shippedCatalog() throws -> LevelCatalog {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Levels", withExtension: nil), "Levels folder missing from the app bundle")
        return try LevelCatalog.load(from: url)
    }

    private func drafts() throws -> [Level] {
        let bundle = Bundle(for: ForgeRunner.self)
        guard let dir = bundle.url(forResource: "drafts", withExtension: nil) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.flatMap { try LevelCatalog.decodeLevels(Data(contentsOf: $0)) }
    }

    private func write(_ level: Level, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try level.encoded(pretty: true).write(to: dir.appendingPathComponent("\(level.id).json"))
    }

    // MARK: - Gates

    /// Fast daily gate: curated levels only, the solution path once at 60 Hz.
    @MainActor
    func testCuratedSmoke() throws {
        let sim = try HeadlessSimulator()
        try sim.selfTest()
        let catalog = try shippedCatalog()
        XCTAssertFalse(catalog.curated.isEmpty, "no curated levels shipped")
        var annotated = 0
        for level in catalog.curated {
            XCTAssertTrue(level.validate().isEmpty, "\(level.id): \(level.validate())")
            guard let a = level.annotation else { log("\(level.id): no annotation yet"); continue }
            annotated += 1
            XCTAssertEqual(a.engineFingerprint, PhysicsConstants.fingerprint, "\(level.id) was verified with other physics constants")
            _ = try replay(level, path: a.solutionPath, profile: .standard, sim: sim)
        }
        log("smoke: \(annotated)/\(catalog.curated.count) curated levels annotated and replayed, fingerprint \(PhysicsConstants.fingerprint)")
    }

    /// Release gate: every shipped level, every validation profile, margin ≥ 1.4.
    /// Turns red when PhysicsConstants change and levels were not re-verified.
    @MainActor
    func testValidateShippedLevels() throws {
        let sim = try HeadlessSimulator()
        try sim.selfTest()
        let catalog = try shippedCatalog()
        var worst = (id: "", margin: Double.infinity)
        for level in catalog.allLevels {
            XCTAssertTrue(level.validate().isEmpty, "\(level.id): \(level.validate())")
            guard let a = level.annotation else { XCTFail("\(level.id): missing annotation"); continue }
            XCTAssertEqual(a.engineFingerprint, PhysicsConstants.fingerprint, "\(level.id): stale annotation")
            XCTAssertLessThanOrEqual(a.solutionPath.count, level.goal.moveBudget, "\(level.id): solution exceeds budget")
            var margins: [Double] = []
            for profile in StepProfile.validationSet {
                let initial = try sim.run(.init(level: level, move: nil, profile: profile))
                XCTAssertEqual(initial.verdict.outcome, .standing, "\(level.id) \(profile): falls before any move")
                margins.append(initial.verdict.margin)
                margins += try replay(level, path: a.solutionPath, profile: profile, sim: sim)
            }
            let m = margins.min() ?? 0
            XCTAssertGreaterThanOrEqual(m, PhysicsConstants.requiredMarginRatio, "\(level.id): margin \(m)")
            if m < worst.margin { worst = (level.id, m) }
        }
        log("validated \(catalog.allLevels.count) levels; tightest margin \(String(format: "%.2f", worst.margin)) on \(worst.id)")
    }

    /// Replays a solution and returns each move's decision margin.
    @MainActor
    private func replay(_ level: Level, path: [String], profile: StepProfile, sim: HeadlessSimulator) throws -> [Double] {
        var margins: [Double] = []
        var log = MoveLog()
        for (i, token) in path.enumerated() {
            let kind: Move.Kind
            if let s = SupportToken.parse(token) {
                kind = .placeSupport(position: Vec2(s.x, level.resolvedFloorY), rotation: s.rotation)
            } else {
                kind = .remove(pieceId: token)
            }
            let r = try sim.run(.init(level: level, base: log, move: kind, profile: profile))
            let expected: MoveResult = i == path.count - 1 ? .won : .continuePlaying
            let got: MoveResult = r.moveResult == .outOfMoves ? .continuePlaying : r.moveResult
            XCTAssertEqual(got, expected, "\(level.id) \(profile) move \(i + 1) \(token)")
            margins.append(r.verdict.margin)
            log.append(kind)
        }
        return margins
    }

    // MARK: - Production

    /// Solves and annotates the hand-made drafts (Tools/LevelForge/drafts) into FORGE_OUT/curated.
    @MainActor
    func testAnnotateCurated() throws {
        let sim = try HeadlessSimulator()
        try sim.selfTest()
        let solver = SolutionSolver(simulator: sim)
        var lines: [String] = []
        for draft in try drafts() {
            let r = solver.solve(draft, verifiedAt: Self.today)
            let line = "\(draft.id)\t\(r.rejection?.rawValue ?? "ok")\tlen=\(r.solutionLength.map(String.init) ?? "-")\tmargin=\(r.marginRatio.map { String(format: "%.2f", $0) } ?? "-")\tstates=\(r.exploredStates)\tevals=\(r.evaluations)\t\(String(format: "%.1fs", r.seconds))\t\(r.detail)"
            log(line)
            lines.append(line)
            if let level = r.annotatedLevel {
                try write(level, to: outDir.appendingPathComponent("curated"))
            }
        }
        try lines.joined(separator: "\n").write(to: outDir.appendingPathComponent("curated-report.tsv"), atomically: true, encoding: .utf8)
    }

    /// Generates, solves and filters pool candidates into FORGE_OUT/pool.
    @MainActor
    func testGeneratePool() throws {
        let sim = try HeadlessSimulator()
        try sim.selfTest()
        let count = Int(env["FORGE_COUNT"] ?? "") ?? 1200
        let base = UInt64(env["FORGE_SEED_BASE"] ?? "") ?? 9000
        var shard = (index: 0, of: 1)
        if let s = env["FORGE_SHARD"]?.split(separator: "/"), s.count == 2, let i = Int(s[0]), let n = Int(s[1]), n > 0 { shard = (i, n) }
        var options = SolutionSolver.Options()
        options.minimumSolutionLength = 2
        options.maxStates = 250
        let solver = SolutionSolver(simulator: sim, options: options)

        var accepted: [Level] = []
        var rejections: [String: Int] = [:]
        var byArchetype: [String: (tried: Int, ok: Int)] = [:]
        let started = Date()
        for k in 0..<count {
            let seed = base + UInt64(k)
            guard Int(seed % UInt64(shard.of)) == shard.index else { continue }
            let candidate = LevelGenerator(seed: seed).make()
            let archetype = String(candidate.id.split(separator: "-")[1])
            byArchetype[archetype, default: (0, 0)].tried += 1
            let r = solver.solve(candidate, verifiedAt: Self.today)
            if let level = r.annotatedLevel, r.unsafeShare >= 0.2 {
                var l = level.tightened(slack: 1)
                l.index = accepted.count + 1
                accepted.append(l)
                byArchetype[archetype]!.ok += 1
            } else {
                rejections[r.rejection?.rawValue ?? "trivial", default: 0] += 1
            }
            if k % 25 == 0 {
                log("seed \(seed): \(accepted.count) accepted, \(String(format: "%.0f", Date().timeIntervalSince(started)))s, \(sim.framesSimulated) frames")
            }
        }
        // Chunk into files of 100 levels.
        let dir = outDir.appendingPathComponent("pool")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (i, start) in stride(from: 0, to: accepted.count, by: 100).enumerated() {
            let chunk = Array(accepted[start..<min(start + 100, accepted.count)])
            let name = String(format: "pool-%02d-%03d.json", shard.index, i)
            try encoder.encode(chunk).write(to: dir.appendingPathComponent(name))
        }
        let summary = """
        candidates: \(count) (shard \(shard.index)/\(shard.of)), accepted: \(accepted.count)
        rejections: \(rejections.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        archetypes: \(byArchetype.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.ok)/\($0.value.tried)" }.joined(separator: ", "))
        mean margin: \(String(format: "%.2f", accepted.compactMap { $0.annotation?.marginRatio }.reduce(0, +) / Double(max(1, accepted.count))))
        solution lengths: \(Dictionary(grouping: accepted, by: { $0.annotation?.solutionPath.count ?? 0 }).mapValues(\.count).sorted { $0.key < $1.key })
        seconds: \(String(format: "%.0f", Date().timeIntervalSince(started))), frames: \(sim.framesSimulated), evaluations: \(sim.jobsRun)
        fingerprint: \(PhysicsConstants.fingerprint)
        """
        log(summary)
        try summary.write(to: outDir.appendingPathComponent("pool-summary-\(shard.index).txt"), atomically: true, encoding: .utf8)
    }
}
