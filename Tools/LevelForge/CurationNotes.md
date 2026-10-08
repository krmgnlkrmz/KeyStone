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
