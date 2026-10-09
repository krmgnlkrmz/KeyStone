# Keystone · Denge Noktası

A calm, offline physics puzzle for iPhone. A structure stands against gravity; remove pieces (and
sometimes place one support) without bringing it down. No timer, no lives, no energy — just a move
budget. When it does fall, the collapse replays in slow motion and marks the piece that gave way.
Every shipped level has a solution verified by an offline solver running the game's own physics.

Swift 6 (strict concurrency) · SwiftUI · SpriteKit · SwiftData · StoreKit 2 · WidgetKit · iOS 17+ ·
portrait · English (base) and Turkish.

## Layout

```
project.yml                 XcodeGen spec; DengeNoktasi.xcodeproj is generated from it and committed
Config/                     xcconfigs: team, bundle/app-group IDs, ad unit IDs (real ones: git-ignored Release.xcconfig)
Packages/BalanceCore        pure Swift game logic (level format, constants + fingerprint, move log, stars,
                            ad pacing, daily picker, streaks, unlocks, support geometry, verdict rules,
                            blame heuristic, tension index + hints) — tested on Linux and macOS
Packages/BalancePhysics     SpriteKit layer shared by the game and LevelForge: body builder, settle
                            evaluator, simulation scene, game scene, replay recorder/scene, skins,
                            headless simulator (SKRenderer), solver, generator
App/                        the iOS app (SwiftUI screens, ads/consent/ATT, store, persistence, Game Center)
Widget/                     Daily widget (small/medium)
Tools/LevelForge/           offline level generation + verification (XCTest in the Simulator)
Tests/AppTests/             app tests (persistence, content gates, physics determinism, localization)
docs/                       physics notes, ads policy, submission checklist
scripts/                    project, asset/strings/sound generators, CI helpers
```

## Getting started

Open `DengeNoktasi.xcodeproj` and run the `DengeNoktasi` scheme. Nothing to install first: the
project is committed, Xcode fetches Google Mobile Ads on its own, and until `Config/Release.xcconfig`
exists every build uses Google's sample ad IDs.

From the command line:

- `make test`: unit tests in the iOS Simulator
- `make core-test`: BalanceCore only, no Xcode needed (works on Linux)
- `make forge-smoke`: curated levels replay their verified solutions

The project is generated from `project.yml` with XcodeGen (the version in `.xcodegen-version`).
After editing `project.yml`, run `make project` and commit the regenerated project; CI fails when the
two disagree.

Before a release: fill in the `Config/Shared.xcconfig` placeholders, copy
`Config/Release.example.xcconfig` to `Config/Release.xcconfig` (git-ignored) with the real AdMob IDs
(see `docs/submission-checklist.md`), then `make forge-validate`. An archive that still has the sample
IDs or the placeholder privacy URL stops with an error.

## Generated files

- `App/Resources/Assets.xcassets` (colour tokens + app icon): `python3 scripts/gen_assets.py`
- `App/Resources/*.xcstrings`, `Widget/*.xcstrings`: `python3 scripts/gen_strings.py`
  (`scripts/check_strings.py` fails CI when a key used in Swift is missing)
- `App/Resources/Sounds`: `python3 scripts/gen_sounds.py`
- `App/Resources/Levels`: LevelForge (`Tools/LevelForge/README.md`)

## Content

- 80 curated levels (`App/Resources/Levels/curated`): 7 hand-made from the design prototype, 73 chosen
  from generator candidates per curriculum slot (`Tools/LevelForge/CurationNotes.md`).
- 1,388 pool levels (`App/Resources/Levels/pool`) for Daily and Endless, across seven archetypes.
- Every one carries an annotation from the offline solver: verified shortest solution, the full
  safe/unsafe/win neighbourhood of every explored state, margin ≥ 1.4 under five frame profiles, and
  the engine fingerprint it was verified with. The release gate (`[forge:validate]`) replays every
  shipped level in a fresh process under the five profiles × eight allocation shifts.

## CI

`.github/workflows/ci.yml`: BalanceCore tests + string coverage on Linux; on macOS: BalanceCore and
BalancePhysics package tests, app build, simulator unit tests, UI smoke tests in the real app (EN, TR,
dark + accessibility-size text, with screenshots), LevelForge smoke. Long runs are started by a commit
message tag (`Tools/LevelForge/README.md` lists them): `[forge:validate]` is the release gate,
`[forge:soak]` plays 50 levels in a row and taps randomly for 30 minutes, `[forge:screens commit]`
captures real-UI screenshots on several devices.
