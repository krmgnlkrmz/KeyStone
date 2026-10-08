# Keystone · Denge Noktası

A calm, offline physics puzzle for iPhone. A structure stands against gravity; remove pieces (and
sometimes place one support) without bringing it down. No timer, no lives, no energy — just a move
budget. When it does fall, the collapse replays in slow motion and marks the piece that gave way.
Every shipped level has a solution verified by an offline solver running the game's own physics.

Swift 6 (strict concurrency) · SwiftUI · SpriteKit · SwiftData · StoreKit 2 · WidgetKit · iOS 17+ ·
portrait · English (base) and Turkish.

## Layout

```
project.yml                 XcodeGen project (the .xcodeproj is generated, not committed)
Config/                     xcconfigs: team, bundle/app-group IDs, ad unit IDs (Release one is git-ignored)
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
scripts/                    bootstrap, asset/strings/sound generators, CI helpers
```

## Getting started

```sh
brew install xcodegen
make bootstrap          # creates Config/Release.xcconfig from the example, generates, resolves packages
open DengeNoktasi.xcodeproj
make test               # unit tests in the iOS Simulator
make core-test          # BalanceCore only, no Xcode needed (works on Linux)
make forge-smoke        # curated levels replay their verified solutions
```

Before a release: fill in `Config/Shared.xcconfig` placeholders and `Config/Release.xcconfig`
(see `docs/submission-checklist.md`), then `make forge-validate`.

## Generated files

- `App/Resources/Assets.xcassets` (colour tokens + app icon): `python3 scripts/gen_assets.py`
- `App/Resources/*.xcstrings`, `Widget/*.xcstrings`: `python3 scripts/gen_strings.py`
  (`scripts/check_strings.py` fails CI when a key used in Swift is missing)
- `App/Resources/Sounds`: `python3 scripts/gen_sounds.py`
- `App/Resources/Levels`: LevelForge (`Tools/LevelForge/README.md`)

## CI

`.github/workflows/ci.yml`: BalanceCore tests + string coverage on Linux; on macOS: BalanceCore and
BalancePhysics package tests, app build, simulator tests, LevelForge smoke. Long forge runs are started by
`workflow_dispatch` or a commit message tag such as `[forge:curate commit]` and commit their output back.
