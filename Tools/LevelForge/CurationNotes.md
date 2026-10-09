# Curation notes — the 80 curated levels

Curated levels live in `App/Resources/Levels/curated/c-NNN.json`. Levels 1–7 are hand-made (ported from
the design prototype, `drafts/`); 8–80 are chosen from generator candidates by `testCuratePlan` against
`curation-plan.json` (written by `scripts/gen_curation_plan.py`). Every curated level is then solved and
annotated by the same solver that verifies the pool; nothing ships without a verified solution.

## Difficulty curve

| Levels | Region | Teaches | Shortest solution | Archetypes |
|---|---|---|---|---|
| 1–3 | Wooden Scaffold | One concept each: tap twice to remove (1), load-bearing pieces fall (2), drag a support (3) | 1–3 | prototype tutorials |
| 4–7 | Wooden Scaffold | Clean drop, pinned lintel, counterweight, twin piers — the four goal shapes | 2–5 | prototype |
| 8–10 | Wooden Scaffold | First free choices: which post can go | 2 | table, tower |
| 11–20 | Stone Arch | **Removal order**: the same pieces in a different order collapse | 2–3 | lintel (drop the keystone), pyramid, stone tower |
| 21–30 | Iron Truss | Order under steel: heavier girders, longer chains | 2–4 | steel table, steel tower |
| 31–40 | Rope Bridge | **Ropes and load transfer**: cutting a rope moves load to a post (or not) | 2–3 | hanger |
| 41–50 | Steel Crane | Ropes + balance: arms, hooks, counterweights | 2–4 | crane hanger, counterweight |
| 51–60 | Counterweight | **Support placement**: place the strut, then take the posts | 3–4 | bridge (placeSupportThenRemove) |
| 61–70 | Counterweight | Balance with an optional strut: remove weights in pairs | 3–5 | counterweight, bridge |
| 71–80 | Keystone | **Combined**: keystone drops, stepped pyramids, longest plans | 3–5 | pyramid, lintel |

Within a region the solution-length band rises in the second half. Move budgets are the shortest
solution plus 1 (plus 2 from level 61), stars are [shortest, shortest + 1, budget].

## The bar for a curated slot

A generator candidate fills a slot only if:

1. The untouched structure stands under all five frame profiles with margin ≥ 1.4.
2. The shortest solution is within the slot's band.
3. At least 20 % of the moves the solver tried collapse something (the level has tension).
4. Not every first move is safe ("every level makes you think").
5. The solution replays identically under all five profiles with margin ≥ 1.4.
6. The goal type matches the slot (51–60 must be support levels).

When no candidate in the slot's 60 seeds qualifies, the forge reports `MISSING` and the slot needs a
different seed range or a hand-made level; it is never filled with a weaker candidate.

## Region gates

A region opens when 70 % of the previous region is done (`UnlockRules`), so a single hard level never
blocks progress. Inside an open region every level is playable; the map highlights the first unplayed one.

## Daily and Endless

The daily level is chosen from curated levels past the tutorial (11–80) plus the pool, by local calendar
day (`DailyLevelPicker`): every device shows the same level on the same day, and no level repeats within
one pass over the list. Endless walks the pool in a per-player order seeded at install
(`LevelCatalog.endlessOrder`).

## Production log

What the forge actually did, so the next person knows why the plan looks the way it does.

- **Hand-made 1–7.** Ported from the design prototype; five verified as drawn. Two needed geometry
  changes the prototype's toy physics hid: *Clean Drop* (4) — the keystone fell only one block height
  (50 pt, 1.25× the 40 pt drop threshold) and ended leaning; the blocks are now 84 pt (margin 1.65).
  *Pinned Lintel* (5) — the 12 pt steel column made the last move a knife-edge; at 16 pt it verifies
  with margin 30, and the order still matters (w1 before w2, because w5 loads the right side).
  Tutorial 2 is gentle on purpose (every first move is safe; the second one teaches), so hand-made
  drafts skip the "too easy" gate; generated levels never do.
- **Generated 8–80, first pass.** 49 of 73 slots filled. Empty: every rope slot (the original hanger
  archetype had no solvable goals under the collapse rules), two-move lintels (lintels need ≥ 3 moves),
  and long bridges/pyramids (they solve in 3). The plan now swaps or widens those slots
  (`OVERRIDES` in `scripts/gen_curation_plan.py`); the second pass filled 7 more.
- **Support slots 51–60** came out as ten variations of one picture (a beam on three posts). The bridge
  archetype now varies post material, a raised footing and stacked loads; even slots were re-curated.
- **Rope slots 31–50** stayed empty through three passes, for two reasons found in the state dumps:
  the overhang's load did not out-lever the beam (so cutting the rope first was safe and the level a
  one-mover), and the solver still offered "cut the rope" after the beam it tied had been removed —
  the scene refused the move and the whole candidate was thrown away. Both are fixed (inner post near
  the middle; `Level.availableRemovals(after:)`).
- **Pool.** First pass: 2,400 candidates from seed 20000 → 1,026 levels in 38 min (bridge 309,
  tower 334, table 167, counterweight 148, pyramid 35, lintel 33, hanger 0). A second pass limited to
  the thin archetypes evens the mix for Endless and Daily.
- `testCuratePlan` keeps every slot that already ships a verified level in its band, so reruns only
  fill gaps (`FORGE_RECURATE=1` or `"recurate": true` per slot redoes them).
- **Fresh-process validation.** Each release-gate run happens in a new process, and SpriteKit's body
  order follows memory addresses, so every run sampled orderings the generator never saw. Runs one to
  four flagged 7, 4 and 4 levels (pool, then curated c-075); a fifth, now under 8 allocation shifts,
  flagged c-075, c-077 and two pool levels. The curated failures were all pyramids ending
  block1 → block3 → shim1: the upper tiers drop 12 pt onto the one remaining middle block, a landing
  that is balanced in most orderings and not in some, while the recorded margin (~2.0, peak movement)
  looks comfortable. Slots 15, 71, 73, 75, 77 and 79 share that finale and were re-curated from fresh
  seeds; curated candidates are verified under 16 shifts (80 combinations), pool levels under 8, and
  pool levels that fail a later gate run are pruned (1,422 → 1,409 so far).

A human playthrough of all 80 is still the last word on the curve; the forge guarantees solvability,
margin and tension, not taste.
