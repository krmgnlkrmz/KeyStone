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
        var failures: [String] = []
        for level in catalog.curated {
            XCTAssertTrue(level.validate().isEmpty, "\(level.id): \(level.validate())")
            guard let a = level.annotation else { log("\(level.id): no annotation yet"); continue }
            annotated += 1
            XCTAssertEqual(a.engineFingerprint, PhysicsConstants.fingerprint, "\(level.id) was verified with other physics constants")
            _ = try replay(level, path: a.solutionPath, profile: .standard, sim: sim, failures: &failures)
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        log("smoke: \(annotated)/\(catalog.curated.count) curated levels annotated and replayed, fingerprint \(PhysicsConstants.fingerprint)")
    }

    /// Re-validation accepts a little less than generation demands (1.4): a fresh simulator may resolve
    /// SpriteKit's internal ordering differently, and a level verified at 1.41 must not flip to red at
    /// 1.39 on noise. A real change (constants, OS physics) moves margins far more than this.
    static let revalidationMargin = 1.25

    /// Release gate: every shipped level, every validation profile, margin ≥ `revalidationMargin`.
    /// Turns red when PhysicsConstants change and levels were not re-verified.
    @MainActor
    func testValidateShippedLevels() throws {
        let sim = try HeadlessSimulator()
        try sim.selfTest()
        let catalog = try shippedCatalog()
        var worst = (id: "", margin: Double.infinity)
        // Every failing level and why. With FORGE_PRUNE=1 a failing pool level is dropped (pool files are
        // rewritten into FORGE_OUT/pool); a failing curated level always fails the gate.
        var failures: [String] = []
        var pruned: Set<String> = []
        let prune = env["FORGE_PRUNE"] == "1"
        for level in catalog.allLevels {
            XCTAssertTrue(level.validate().isEmpty, "\(level.id): \(level.validate())")
            guard let a = level.annotation else { XCTFail("\(level.id): missing annotation"); continue }
            XCTAssertEqual(a.engineFingerprint, PhysicsConstants.fingerprint, "\(level.id): stale annotation")
            XCTAssertLessThanOrEqual(a.solutionPath.count, level.goal.moveBudget, "\(level.id): solution exceeds budget")
            XCTAssertGreaterThanOrEqual(a.marginRatio ?? 0, PhysicsConstants.requiredMarginRatio, "\(level.id): verified margin below 1.4")
            var margins: [Double] = []
            let before = failures.count
            for profile in StepProfile.validationSet {
                let initial = try sim.run(.init(level: level, move: nil, profile: profile))
                if initial.verdict.outcome != .standing { failures.append("\(level.id)\t\(profile): falls before any move") }
                margins.append(initial.verdict.margin)
                for jitter in Self.validationJitters {
                    margins += try replay(level, path: a.solutionPath, profile: profile, jitter: jitter, sim: sim, failures: &failures)
                }
            }
            let m = margins.min() ?? 0
            if m < Self.revalidationMargin { failures.append("\(level.id)\tmargin \(m)") }
            if failures.count > before {
                if level.pack == .pool && prune {
                    pruned.insert(level.id)
                    log("pruned \(level.id): \(failures[before...].joined(separator: "; "))")
                } else {
                    XCTFail(failures[before...].joined(separator: "; "))
                }
            }
            if m < worst.margin { worst = (level.id, m) }
        }
        log("validated \(catalog.allLevels.count) levels; tightest margin \(String(format: "%.2f", worst.margin)) on \(worst.id); \(failures.count) failures")
        try failures.joined(separator: "\n").write(to: outDir.appendingPathComponent("validate-failures.txt"), atomically: true, encoding: .utf8)
        if !pruned.isEmpty { try writePrunedPool(without: pruned) }
    }

    /// Allocation shifts the release gate samples per profile (see `HeadlessSimulator.Job.allocationJitter`).
    static let validationJitters = [0, 23, 71]

    /// Rewrites every shipped pool file that held a pruned level into FORGE_OUT/pool (same names).
    private func writePrunedPool(without ids: Set<String>) throws {
        let root = try XCTUnwrap(Bundle.main.url(forResource: "Levels", withExtension: nil)).appendingPathComponent("pool")
        let dir = outDir.appendingPathComponent("pool")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            let levels = try LevelCatalog.decodeLevels(Data(contentsOf: url))
            let kept = levels.filter { !ids.contains($0.id) }
            guard kept.count != levels.count else { continue }
            try encoder.encode(kept).write(to: dir.appendingPathComponent(url.lastPathComponent))
        }
        log("pruned \(ids.count) pool levels: \(ids.sorted().joined(separator: ", "))")
    }

    /// Replays a solution and returns each move's decision margin.
    @MainActor
    private func replay(_ level: Level, path: [String], profile: StepProfile, jitter: Int = 0, sim: HeadlessSimulator,
                        failures: inout [String]) throws -> [Double] {
        var margins: [Double] = []
        var log = MoveLog()
        for (i, token) in path.enumerated() {
            let kind: Move.Kind
            if let s = SupportToken.parse(token) {
                kind = .placeSupport(position: Vec2(s.x, level.resolvedFloorY), rotation: s.rotation)
            } else {
                kind = .remove(pieceId: token)
            }
            let r = try sim.run(.init(level: level, base: log, move: kind, profile: profile, allocationJitter: jitter))
            let expected: MoveResult = i == path.count - 1 ? .won : .continuePlaying
            let got: MoveResult = r.moveResult == .outOfMoves ? .continuePlaying : r.moveResult
            if got != expected { failures.append("\(level.id)\t\(profile) j\(jitter) move \(i + 1) \(token): \(got) ≠ \(expected)") }
            margins.append(r.verdict.margin)
            log.append(kind)
        }
        return margins
    }

    // MARK: - Production

    /// Solves and annotates the hand-made drafts (Tools/LevelForge/drafts) into FORGE_OUT/curated.
    /// Drafts whose id starts with "x-" are geometry variants under trial: verified and logged, never shipped.
    /// Hand-made levels may be gentle on the first move (tutorials), so the "too easy" gate is off here.
    @MainActor
    func testAnnotateCurated() throws {
        let sim = try HeadlessSimulator()
        try sim.selfTest()
        var options = SolutionSolver.Options()
        options.rejectTooEasy = false
        let solver = SolutionSolver(simulator: sim, options: options)
        var lines: [String] = []
        for draft in try drafts() {
            let r = solver.solve(draft, verifiedAt: Self.today)
            let line = "\(draft.id)\t\(r.rejection?.rawValue ?? "ok")\tlen=\(r.solutionLength.map(String.init) ?? "-")\tmargin=\(r.marginRatio.map { String(format: "%.2f", $0) } ?? "-")\tunsafe=\(String(format: "%.2f", r.unsafeShare))\tstates=\(r.exploredStates)\tevals=\(r.evaluations)\t\(String(format: "%.1fs", r.seconds))\t\(r.detail)\t\(r.annotatedLevel?.annotation?.solutionPath.joined(separator: ",") ?? "")"
            log(line)
            lines.append(line)
            if r.rejection != nil || draft.id.hasPrefix("x-") {
                for state in r.states { log("   \(draft.id) " + Self.describe(state)) }
            }
            if var level = r.annotatedLevel, !draft.id.hasPrefix("x-") {
                // Three stars always means the verified shortest solution, whatever the draft guessed.
                if let len = r.solutionLength {
                    let t = level.goal.normalizedThresholds, budget = level.goal.moveBudget
                    level.goal.starThresholds = [len, min(max(t.count > 1 ? t[1] : len, len), budget), budget]
                }
                try write(level, to: outDir.appendingPathComponent("curated"))
            }
        }
        try lines.joined(separator: "\n").write(to: outDir.appendingPathComponent("curated-report.tsv"), atomically: true, encoding: .utf8)
    }

    /// "'w1,w5' safe[w2] unsafe[t1→w4 1.8] win[w2]" — one line per explored state in the forge log.
    static func describe(_ s: StateMoves) -> String {
        let unsafe = s.unsafeMoves.sorted { $0.key < $1.key }
            .map { "\($0.key)→\($0.value) \(String(format: "%.2f", s.severity?[$0.key] ?? 0))" }
        let safe = s.safe.map { "\($0) \(String(format: "%.2f", s.severity?[$0] ?? 0))" }
        return "'\(s.state)' safe[\(safe.joined(separator: ", "))] unsafe[\(unsafe.joined(separator: ", "))] win[\((s.win ?? []).joined(separator: ", "))]"
    }

    /// One curriculum slot in Tools/LevelForge/curation-plan.json.
    struct Slot: Decodable {
        var index: Int
        var region: String
        var archetype: String
        var seed: UInt64
        var attempts: Int?
        var minLength: Int
        var maxLength: Int
        var slack: Int?
        var minUnsafe: Double?
        var goal: String?
        var name: [String: String]
        /// Regenerate even when a verified level already fills the slot (after a generator change).
        var recurate: Bool?
    }

    struct Plan: Decodable { var slots: [Slot] }

    /// Fills each curriculum slot with the first generator candidate that passes the solver and the
    /// slot's own bar (solution length, tension, goal type). Writes FORGE_OUT/curated/c-NNN.json.
    @MainActor
    func testCuratePlan() throws {
        let path = try XCTUnwrap(env["FORGE_PLAN"], "FORGE_PLAN not set")
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let sim = try HeadlessSimulator()
        try sim.selfTest()
        var options = SolutionSolver.Options()
        options.maxStates = 300
        let solver = SolutionSolver(simulator: sim, options: options)
        var lines: [String] = []
        let started = Date()
        // Slots that already ship a verified level within their band are kept, so a rerun only fills gaps
        // (FORGE_RECURATE=1 redoes every slot).
        let shipped: [Int: Level] = env["FORGE_RECURATE"] == "1" ? [:] : Dictionary((try? shippedCatalog())?.curated.map { ($0.index, $0) } ?? [],
                                                                      uniquingKeysWith: { a, _ in a })
        for slot in plan.slots {
            if slot.recurate != true, let kept = shipped[slot.index], let a = kept.annotation, a.engineFingerprint == PhysicsConstants.fingerprint,
               (slot.minLength...slot.maxLength).contains(a.solutionPath.count) {
                lines.append("\(slot.index)\tkept\t\(kept.id)\tlen \(a.solutionPath.count)")
                continue
            }
            guard let archetype = LevelGenerator.Archetype(rawValue: slot.archetype), let region = Region(rawValue: slot.region) else {
                lines.append("\(slot.index)\tBAD-SLOT"); continue
            }
            var found: (Level, SolutionSolver.Report, UInt64, Int)?
            var tries = 0
            for k in 0..<(slot.attempts ?? 40) {
                tries = k + 1
                let seed = slot.seed + UInt64(k)
                let candidate = LevelGenerator(seed: seed).make(archetype: archetype, region: region, pack: .curated, index: slot.index)
                if let g = slot.goal, g != candidate.goal.type.rawValue { continue }
                let r = solver.solve(candidate, verifiedAt: Self.today)
                guard let level = r.annotatedLevel, let len = r.solutionLength,
                      (slot.minLength...slot.maxLength).contains(len), r.unsafeShare >= (slot.minUnsafe ?? 0.2) else { continue }
                found = (level, r, seed, k)
                break
            }
            guard let (level, report, seed, _) = found else {
                let line = "\(slot.index)\tMISSING\t\(slot.archetype)\ttried \(tries) from seed \(slot.seed)"
                log(line); lines.append(line); continue
            }
            var l = level.tightened(slack: slot.slack ?? 1)
            l.id = String(format: "c-%03d", slot.index)
            l.index = slot.index
            l.name = slot.name
            try write(l, to: outDir.appendingPathComponent("curated"))
            let line = "\(slot.index)\t\(slot.archetype)\tseed \(seed)\tlen \(report.solutionLength ?? 0)\tbudget \(l.goal.moveBudget)\tmargin \(String(format: "%.2f", report.marginRatio ?? 0))\tunsafe \(String(format: "%.2f", report.unsafeShare))\ttries \(tries)\t\(String(format: "%.0fs", Date().timeIntervalSince(started)))"
            log(line)
            lines.append(line)
        }
        try lines.joined(separator: "\n").write(to: outDir.appendingPathComponent("curate-report.tsv"), atomically: true, encoding: .utf8)
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

        // FORGE_ARCHETYPES=hanger,lintel limits a run to some archetypes (to even out the pool's mix).
        let only = Set((env["FORGE_ARCHETYPES"] ?? "").split(separator: ",").compactMap { LevelGenerator.Archetype(rawValue: String($0)) })
        var accepted: [Level] = []
        var rejections: [String: Int] = [:]
        var samples: [String: [String]] = [:]
        var byArchetype: [String: (tried: Int, ok: Int)] = [:]
        let started = Date()
        // Files of 100 levels, written as they fill so a crash late in a long run keeps earlier work.
        // The seed base is in the name: runs with different bases never overwrite each other.
        let dir = outDir.appendingPathComponent("pool")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func writeChunk(_ i: Int) throws {
            let chunk = Array(accepted[(i * 100)..<min(i * 100 + 100, accepted.count)])
            try encoder.encode(chunk).write(to: dir.appendingPathComponent("pool-\(base)-\(shard.index)of\(shard.of)-\(i).json"))
        }
        for k in 0..<count {
            let seed = base + UInt64(k)
            guard Int(seed % UInt64(shard.of)) == shard.index else { continue }
            let generator = LevelGenerator(seed: seed)
            let candidate = only.isEmpty ? generator.make() : generator.make(archetype: only.sorted { $0.rawValue < $1.rawValue }[Int(seed % UInt64(only.count))])
            let archetype = String(candidate.id.split(separator: "-")[1])
            byArchetype[archetype, default: (0, 0)].tried += 1
            let r = solver.solve(candidate, verifiedAt: Self.today)
            if let level = r.annotatedLevel, r.unsafeShare >= 0.2 {
                var l = level.tightened(slack: 1)
                l.index = accepted.count + 1
                accepted.append(l)
                byArchetype[archetype]!.ok += 1
                if accepted.count % 20 == 0 { try writeChunk((accepted.count - 1) / 100) }
            } else {
                let reason = r.rejection?.rawValue ?? "trivial"
                rejections[reason, default: 0] += 1
                if samples[reason, default: []].count < 3 { samples[reason, default: []].append("\(candidate.id): \(r.detail)") }
            }
            if k % 50 == 0 {
                let perArchetype = byArchetype.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.ok)/\($0.value.tried)" }.joined(separator: " ")
                log("seed \(seed): \(accepted.count) accepted, \(String(format: "%.0f", Date().timeIntervalSince(started)))s · \(perArchetype)")
            }
        }
        if !accepted.isEmpty { try writeChunk((accepted.count - 1) / 100) }
        let summary = """
        candidates: \(count) (shard \(shard.index)/\(shard.of)), accepted: \(accepted.count)
        rejections: \(rejections.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        samples: \(samples.sorted { $0.key < $1.key }.flatMap(\.value).joined(separator: " | "))
        archetypes: \(byArchetype.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.ok)/\($0.value.tried)" }.joined(separator: ", "))
        mean margin: \(String(format: "%.2f", accepted.compactMap { $0.annotation?.marginRatio }.reduce(0, +) / Double(max(1, accepted.count))))
        solution lengths: \(Dictionary(grouping: accepted, by: { $0.annotation?.solutionPath.count ?? 0 }).mapValues(\.count).sorted { $0.key < $1.key })
        seconds: \(String(format: "%.0f", Date().timeIntervalSince(started))), frames: \(sim.framesSimulated), evaluations: \(sim.jobsRun)
        fingerprint: \(PhysicsConstants.fingerprint)
        """
        log(summary)
        try summary.write(to: outDir.appendingPathComponent("pool-summary-\(base)-\(shard.index)of\(shard.of).txt"), atomically: true, encoding: .utf8)
    }
}
