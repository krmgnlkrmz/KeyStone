# LevelForge

Offline level generation and verification. It runs as an XCTest target (`LevelForgeTests`, scheme
`LevelForge`) inside the iOS Simulator, hosted by the app, so it uses the shipping SpriteKit and the
exact same `BalancePhysics` code as the game.

## Commands

```sh
make forge-smoke       # daily: curated levels, solution path once at 60 Hz
make forge-validate    # release gate: all levels, 5 frame profiles, margin ≥ 1.4, fingerprint
make forge-curated     # solve + annotate Tools/LevelForge/drafts/*.json → forge-out/curated/
make forge-pool FORGE_COUNT=1200 FORGE_SEED_BASE=9000   # → forge-out/pool/pool-*.json
```

Environment variables reach the test process through xcodebuild's `TEST_RUNNER_` prefix
(`TEST_RUNNER_FORGE_OUT`, `TEST_RUNNER_FORGE_COUNT`, `TEST_RUNNER_FORGE_SEED_BASE`,
`TEST_RUNNER_FORGE_SHARD=i/n`). The Makefile does this for you.

On GitHub Actions: run the **CI** workflow manually (`workflow_dispatch`) with `forge` set to
`validate`, `curated` or `pool`; outputs are uploaded as the `forge-out` artifact.

## How it is fast without breaking determinism

SpriteKit has no public world-step call, but `SKRenderer.update(atTime:)` runs a full SpriteKit frame
(including physics) for the timestamp we give it. `HeadlessSimulator` feeds it exact frame times, so a
2 s settle window takes milliseconds instead of 2 s, and every run is reproducible. The game runs the same
`SimulationScene` from `SKView` at 60 Hz. `selfTest()` refuses to run if physics does not advance.

The simulator is single-threaded on purpose (SpriteKit is main-thread only). To go wider, shard by seed
across several simulators/processes (`FORGE_SHARD=0/4`, `1/4`, …), not threads.

## Pipeline

1. **Generate** (`LevelGenerator`, seeded Mersenne Twister): one of seven archetypes — table, tower,
   lintel, counterweight, bridge (support), hanger (ropes), pyramid — with jittered sizes, materials,
   counts and load positions. Pieces are placed so their surfaces touch exactly.
2. **Solve** (`SolutionSolver`): the untouched structure must stand under all five profiles with margin;
   then breadth-first search over states within the move budget. Each edge is "rebuild state, settle,
   make move, evaluate". Every explored state records its safe / unsafe (with the blamed piece and
   severity) / winning moves.
3. **Filter**: unsolvable, too easy (every first move safe), too short (pool: < 2 moves), not enough
   tension (pool: < 20 % unsafe moves), inconsistent between profiles, or margin < 1.4 → rejected.
4. **Tighten** (pool): budget = shortest solution + 1, stars [L, L+1, budget], annotation trimmed.
5. **Write** JSON with `annotation.engineFingerprint` = `PhysicsConstants.fingerprint`.

## Curated levels

80 curated levels follow the curriculum in `CurationNotes.md`. The first seven come from the design
prototype (hand-made, in `drafts/`); the rest are chosen from generator candidates per slot and then
annotated by the same solver. Shipping a curated level means its JSON in
`App/Resources/Levels/curated/` carries an annotation produced by this tool.
