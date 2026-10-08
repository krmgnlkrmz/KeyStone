import Foundation
import Testing
@testable import BalanceCore

@Suite("Tension index and hints")
struct TensionIndexTests {
    func annotated(fingerprint: String = PhysicsConstants.fingerprint) -> Level {
        bridgeLevel(annotation: Annotation(
            solutionPath: ["+sup@0", "l"],
            stateMoves: [
                StateMoves(state: "", safe: ["load", "+sup@0"], unsafe: ["l": "r", "r": "l", "beam": "load"],
                           severity: ["load": 0.1, "+sup@0": 0.05, "l": 1.4, "r": 3.2, "beam": 2.5]),
                StateMoves(state: "+sup@0", safe: ["l", "r", "load"], unsafe: ["beam": "load"],
                           severity: ["l": 0.4, "r": 0.5, "load": 0.1, "beam": 2.1], win: ["l", "r"]),
                StateMoves(state: "load", safe: [], unsafe: ["l": "beam", "r": "beam", "beam": "l"]),
            ],
            verifiedAt: "2026-10-08", engineFingerprint: fingerprint))
    }

    @Test func fingerprintMismatchDisablesTheIndex() {
        let index = TensionIndex(level: annotated(fingerprint: "spk-0-30hz-dead"))
        #expect(!index.isUsable)
        #expect(index.tiers(stateKey: "", revealCritical: true).isEmpty)
        #expect(index.hint(stateKey: "", movesLeft: 3) == nil)
        #expect(index.mismatchReason?.contains("spk-0-30hz-dead") == true)
    }

    @Test func missingAnnotationIsNotUsable() {
        #expect(!TensionIndex(level: bridgeLevel()).isUsable)
    }

    @Test func tiersHideCriticalUntilAHintWasTaken() {
        let index = TensionIndex(level: annotated())
        let hidden = index.tiers(stateKey: "", revealCritical: false)
        #expect(hidden["load"] == TensionTier.none)
        #expect(hidden["l"] == .tense)
        #expect(hidden["r"] == .tense)
        #expect(hidden["beam"] == .tense)
        let shown = index.tiers(stateKey: "", revealCritical: true)
        #expect(shown["r"] == .critical)
        #expect(shown["beam"] == .critical)
        #expect(shown["+sup@0"] == nil)
        #expect(index.tiers(stateKey: "+sup@0", revealCritical: false)["l"] == .light)
    }

    @Test func hintFollowsTheSolutionPathThenSearches() {
        let index = TensionIndex(level: annotated())
        #expect(index.hint(stateKey: "", movesLeft: 3) == "+sup@0")
        #expect(index.hint(stateKey: "+sup@0", movesLeft: 2) == "l")
        // Off the path: removing "load" first leads nowhere.
        #expect(index.hint(stateKey: "load", movesLeft: 2) == nil)
        #expect(index.isDeadEnd(stateKey: "load", movesLeft: 2))
        // Unknown state: no claim either way.
        #expect(!index.isDeadEnd(stateKey: "zzz", movesLeft: 2))
    }

    @Test func hintRespectsTheRemainingBudget() {
        let index = TensionIndex(level: annotated())
        #expect(index.hint(stateKey: "", movesLeft: 1) == nil)
    }

    @Test func culpritComesFromTheAnnotation() {
        let index = TensionIndex(level: annotated())
        #expect(index.culprit(stateKey: "", move: "r") == "l")
        #expect(index.culprit(stateKey: "", move: "load") == nil)
    }
}

@Suite("Fingerprint, snapshot, catalog")
struct MiscTests {
    @Test func fingerprintShape() {
        let fp = PhysicsConstants.fingerprint
        #expect(fp.hasPrefix("\(PhysicsConstants.engineFamily)-\(PhysicsConstants.stepHz)hz-"))
        #expect(fp.count == "spk-1-60hz-0000".count)
        #expect(fp == PhysicsConstants.fingerprint)
    }

    @Test func stableHashIsKnownAndSensitive() {
        #expect(StableHash.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(StableHash.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
        let base = PhysicsConstants.canonicalDescription
        #expect(StableHash.fnv1a64(base) != StableHash.fnv1a64(base.replacingOccurrences(of: "tr=26.0", with: "tr=26.5")))
    }

    @Test func snapshotRoundTripAndStreak() throws {
        let level = try Fixtures.level("c-004")
        let snap = ProgressSnapshot(writtenAt: Date(timeIntervalSince1970: 1_791_400_000), dailyStreak: 6,
                                    lastDailyCompletedKey: "2026-10-07", totalStars: 41,
                                    days: [.init(dayKey: "2026-10-08", levelId: level.id, par: 2, silhouette: Silhouette(level: level))])
        let back = try ProgressSnapshot.decode(snap.encoded())
        #expect(back == snap)
        #expect(back.streak(on: "2026-10-08") == 6)
        #expect(!back.isSolved(dayKey: "2026-10-08"))
        #expect(back.day(for: "2026-10-08")?.silhouette.shapes.contains { $0.kind == .keystone } == true)
    }

    @Test func catalogLoadsSinglesAndArrays() throws {
        let one = try Fixtures.data("c-001")
        #expect(try LevelCatalog.decodeLevels(one).count == 1)
        let l1 = try Fixtures.level("c-001"), l4 = try Fixtures.level("c-004")
        let array = try JSONEncoder().encode([l1, l4])
        #expect(try LevelCatalog.decodeLevels(array).map(\.id) == ["c-001", "c-004"])
    }

    @Test func endlessOrderIsAPerPlayerPermutation() {
        let pool = (1...50).map { i in
            Level(id: "p-\(i)", pack: .pool, region: "stone_arch", index: i,
                  goal: Goal(type: .removeTargetsKeepStanding, targetPieceIds: [], moveBudget: 1, starThresholds: [1, 1, 1]),
                  pieces: [])
        }
        let catalog = LevelCatalog(curated: [], pool: pool)
        let a = catalog.endlessOrder(seed: 42), b = catalog.endlessOrder(seed: 42), c = catalog.endlessOrder(seed: 43)
        #expect(a == b)
        #expect(a != c)
        #expect(Set(a).count == 50)
        #expect(catalog.endlessLevel(seed: 42, cursor: 50)?.id == a[0])
    }

    @Test func catalogRegionsAndNext() throws {
        let catalog = LevelCatalog(curated: [try Fixtures.level("c-004"), try Fixtures.level("c-001")], pool: [])
        #expect(catalog.curated.map(\.id) == ["c-001", "c-004"])
        #expect(catalog.next(after: "c-001")?.id == "c-004")
        #expect(catalog.next(after: "c-004") == nil)
        #expect(catalog.regions.count == 1)
        #expect(catalog.regions[0].region == .woodScaffold)
    }
}
