# Physics notes — decisions and why

The riskiest part of Keystone is that the game and the level verifier must agree about what stands
and what falls. Everything below serves that.

## One engine, one set of numbers

- Every physics value lives in `Packages/BalanceCore/Sources/BalanceCore/PhysicsConstants.swift`:
  gravity, step rate, windows, collapse tolerances, per-material density / friction / restitution /
  damping, support geometry. Level JSON names a material; it never carries a physics number.
- `StructureSceneBuilder` (BalancePhysics) is the only place an `SKPhysicsBody` is configured. The
  game scene and the headless simulator both call it, in the same order: floor, pieces in file order,
  placed supports in move order, joints in file order. SpriteKit's solver is sensitive to body order,
  so this order never changes.
- `PhysicsConstants.fingerprint` (currently `spk-1-60hz-f029`) is an FNV-1a hash of the canonical text
  of every constant plus an "engine family" tag we bump when an OS update changes SpriteKit's solver.
  Each level's annotation stores the fingerprint it was verified with. At runtime a mismatch disables
  tension marks and hints for that level (it stays playable) and is logged. `testValidateShippedLevels`
  fails on any mismatch, so changing a constant without re-verifying levels turns the release gate red.

## Stepping: game vs. LevelForge

SpriteKit has no public "step the world by dt" call. Two consequences, two answers:

1. **The game** runs in `SKView` at 60 fps (`preferredFramesPerSecond = 60`, `physicsWorld.speed = 1`).
   `SimulationScene` measures each frame's step from `update(_:)` timestamps (clamped to 1/20 s) and runs
   all logic in `didSimulatePhysics()`, i.e. after SpriteKit has stepped. Windows are counted in physics
   time, so a dropped frame makes one sample cover more simulated time — the decision is never taken
   earlier than 2 s of simulated time.
2. **LevelForge** drives the *same* `SimulationScene` with `SKRenderer.update(atTime:)`, which runs one
   complete SpriteKit frame cycle (update → actions → physics → didSimulatePhysics) for the timestamp we
   pass. Passing exact 1/60 s increments gives the game's nominal timing, deterministically, as fast as
   the CPU allows. `HeadlessSimulator.selfTest()` drops a box and checks it fell, so if a future OS stops
   simulating physics in `SKRenderer`, the forge fails loudly instead of producing wrong annotations.
   (Verified in CI on the iOS 26 simulator.)

No speed-up tricks (`physicsWorld.speed`, larger steps) are used anywhere.

**What is and is not bit-identical.** SpriteKit derives each step from absolute timestamps, so every
forge job starts on a fresh `SKRenderer` at the same clock origin; the same job then sees bit-identical
frame times no matter what ran before. What the forge cannot control is SpriteKit's internal ordering of
bodies, which can differ between simulator instances: an exactly symmetric structure may settle a hair
to the left in one process and a hair to the right in another (observed: 0.004 rad). Decisions do not
depend on such hairs — that is what the margin and the five profiles are for — so the tests compare
decisions exactly and settled poses with a tolerance (`sameJobSameDecision`). Re-validation of shipped
levels (`testValidateShippedLevels`) accepts margin ≥ 1.25 against generation's 1.4 for the same reason.
Replays are never re-simulated (below), so they are exact.

## The decision rule (tolerant on purpose)

`SettleRules.verdict` (BalanceCore, unit-tested on Linux) decides, from per-body measurements:

- A watched body collapses when its peak distance from its **design pose** reaches
  `collapseTranslation` (26 pt) or its peak rotation reaches `collapseRotation` (0.30 rad) at any time
  in the window. Measuring against the design pose (not the previous pose) stops small drifts from
  accumulating over several moves.
- Otherwise the structure is standing once `settleWindow` (2 s) has passed **and** every body is resting
  (`restingSpeed` 6 pt/s, `restingAngularSpeed` 0.12 rad/s); if it never rests, the window ends at
  `maxSimSeconds` (4 s) and the tolerance alone decides. A structure that sways and stops is a success.
- `dropOnlyTarget`: targets are excluded from the collapse check and count as dropped once their centre
  is `dropDistance` (40 pt) below the design pose.
- After a collapse is detected the window keeps recording for `collapseTail` (1.6 s in the game, 0.6 s
  in the forge) so the replay shows the fall and the blame heuristic has frames to look at.

**Margins.** Every verdict reports `margin`: `1/worstRatio` for standing, `worstRatio` for collapse, and
the drop distance ratio for drops. The forge replays each level's solution under five frame-timing
profiles — 60 Hz, 120 Hz, a dropped frame every 7th, display-link jitter, and a struggling 45 Hz device —
and rejects the level unless all agree and the smallest margin is ≥ 1.4 (the decision is ≥ 40 % away
from its threshold). Narrow levels never ship; a narrow level is exactly where two devices could disagree.

## Bodies

- Restitution 0–0.05, generous damping (linear 0.3–0.5, angular 0.7–1.0): structures settle quickly and
  behave less chaotically.
- `usesPreciseCollisionDetection` only for pieces thinner than 16 pt.
- The floor is a static edge spanning ±4000 pt at `floorY` (per level), friction 0.9.
- **Supports are anchored struts** (static bodies standing on the floor). A free-standing 14 pt steel
  post would topple under any off-centre load, which reads as a bug rather than a puzzle. The strut is
  placed with 0.5 pt clearance so a sagging beam settles onto it instead of being pushed up.
- Support positions are a finite set (`SupportGeometry.candidates`): three per piece with room beneath it
  (near each end and the middle), snapped to the 8 pt grid. The solver explores exactly these, and the
  game's drag ghost snaps to the nearest one, so a placed support always produces a state the annotation
  knows. Only upright struts in v1 (`supportAngles = [0]`); tilted struts (15° steps) are supported by the
  data format (`+sup@x r deg`) but multiply the search, so they wait for a level that needs them.
- Ropes are `SKPhysicsJointLimit` joints; a rope with an `id` and `removable: true` can be cut (it is a
  move like removing a piece). Pins are `SKPhysicsJointPin`.
- A rope leaves with either piece it ties: removing that piece removes the joint too, and from then on
  the rope is no longer a move (`Level.availableRemovals(after:)`, used by the solver; the game simply
  stops showing it). Goals count only ropes that were cut, never ones that vanished with a piece.
- Bodies are rigid: a beam never sags. A post that only shares load with others can always go; what
  makes a level is leverage — a load beyond a support, an end hanging from a rope, a column under a
  balance. The generator's archetypes are built around exactly that (see `LevelGenerator`).

## Undo is replay

`MoveLog` is the state. Undo drops the last move and calls `SimulationScene.load(log:)`, which rebuilds
the structure from scratch with all remaining moves applied at t = 0 (no windows between them) and runs
one quiet settle. The state after undo is therefore, by definition, the state the solver evaluates
(`SolutionSolver` evaluates every transition the same way: rebuild the base state, settle, make the move).
`PhysicsTests.testUndoMatchesForwardPlay` checks forward play (one scene, a window per move) against the
rebuild within 2 pt / 0.02 rad.

## Replays are recordings

`ReplayRecorder` stores every watched body's pose each simulated frame (ring buffer, ≤ 4 s at up to
120 Hz). `ReplayScene` plays it back with physics off, assigning transforms directly, with linear
interpolation for 0.25× / 0.5× and scrubbing. Nothing is re-simulated, so the replay is identical every
time and on every device (`PhysicsTests.testReplayIsIdenticalEveryTime`).

## Blame

1. Offline annotation: `stateMoves[state].unsafe[move]` — measured by the solver with the full recording.
2. Runtime heuristic (`CulpritHeuristic`, BalanceCore): in the first 0.5 s after the collapse starts, find
   the watched body that rotates most; blame the nearest body under its centre of mass at that moment
   (or the body itself when nothing is below). Used when the annotation has no entry.
3. Neither: the replay plays without a label.

## Tension marks

SpriteKit doesn't expose contact forces, so the three-tier mark is not computed at runtime. It comes from
the annotation: for the current state, a safe move with severity ≥ 0.25 shows *light*, an unsafe move
shows *tense*, and an unsafe move with severity ≥ 2 shows *critical* — but only after the player took a
hint on this attempt; before that it shows as *tense*. "It implies, it doesn't tell": the marks describe
the next move only, never the plan, and the player still has to find an order that fits the budget.
While a move settles the marks are hidden and a faint continuous haptic plays.

## Known limits

- States are keyed by the *set* of moves. Two orders that place a support before vs. after removing a
  piece could, in principle, give that support a different height. The solver keeps the first order it
  found; the game resolves supports in the order the player made them. No shipped level depends on this.
- Ropes can swing past the 26 pt tolerance without "collapsing" anything meaningful; rope levels that do
  so are rejected by the margin check rather than special-cased.
