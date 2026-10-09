# Ads policy

Code may not violate this file. `AdsCoordinator` is the single entry point; `AdFrequencyCap`
(BalanceCore, unit-tested) holds the pacing rules.

## SDK

- Google Mobile Ads via SPM, pinned to **12.14.0** (`project.yml`, `exactVersion`), which brings
  User Messaging Platform **3.1.0**. Both were the latest stable releases when resolved on 2026-10-08.
- API names are taken from the resolved module (`scripts/ci-sdk-report.sh`, CI job "Ads SDK report",
  run by adding `[sdk-report]` to a commit message or by `workflow_dispatch`): `MobileAds.shared`,
  `BannerView`, `currentOrientationAnchoredAdaptiveBanner(width:)`, `InterstitialAd.load(with:request:)`,
  `RewardedAd.load(with:request:)`, `present(from:)`, `FullScreenContentDelegate`, UMP's
  `ConsentInformation.shared`, `ConsentForm.loadAndPresentIfRequired(from:)`,
  `ConsentForm.presentPrivacyOptionsForm(from:)`.
- All ad code is `@MainActor`. Completion-based SDK calls are made inside `withCheckedContinuation` from
  main-actor functions, so the SDK is always entered on the main thread.
- IDs come from `Config/*.xcconfig` → `Info.plist` (`GADApplicationIdentifier`, `DNAdUnitBanner`,
  `DNAdUnitInterstitial`, `DNAdUnitRewarded`). Debug uses Google's sample IDs. Release IDs live in the
  git-ignored `Config/Release.xcconfig`.
- `SKAdNetworkItems` is Google's published list (50 identifiers on 2026-10-08), refreshed with
  `scripts/update-skadnetworks.sh`.

## Consent order (launch)

1. Splash. `ConsentInformation.requestConsentInfoUpdate` (UMP).
2. `ConsentForm.loadAndPresentIfRequired` — only when UMP requires it.
3. If ads may be requested and ATT is undetermined: our one-screen primer ("Before iOS asks").
4. `ATTrackingManager.requestTrackingAuthorization`.
5. `MobileAds.shared.start()` — **only** in `AdsCoordinator.startIfAllowed()`, only when
   `canRequestAds` is true (logged: "MobileAds.start after consent").
6. Preload one interstitial and one rewarded.

UMP errors (offline) are logged and swallowed; the game opens normally, ads simply don't load.
Declining ATT changes nothing in the game; ads are non-personalised.

Settings → **Privacy settings** calls `presentPrivacyOptionsForm` and is shown only when
`privacyOptionsRequirementStatus == .required` (Google's rule). Settings → **Privacy Policy** opens
`PRIVACY_URL` from the xcconfig.

## Placements

| Screen | Banner | Interstitial | Rewarded |
|---|---|---|---|
| Launch / consent | — | never | — |
| Main Menu | bottom, inside safe area | never | — |
| Level Map | bottom, inside safe area | never | — |
| Settings (sheet) | bottom, inside safe area | never | — |
| Game | **none** | **never** | Hint (opt-in) |
| Pause | — | never | Hint |
| Collapse Replay | **none** | never | Back to last move |
| Out of moves | — | on exit only (below) | — |
| Level Clear | — | on exit only (below) | See the perfect solution (< 3★) |
| Daily sheet | covered by the sheet | never | — |

- **Banner**: adaptive anchored banner; its height is computed before loading and the slot is reserved,
  so an unfilled or offline banner shows a hatched placeholder and the layout never jumps.
- **Interstitial**: only when leaving Level Clear / Collapse / Out-of-moves towards the Map or the next
  level. Rules (`AdFrequencyCap`): never during the first 3 clears (tutorial); then at least 3 clears
  between interstitials; at least 90 s between interstitials; at least 45 s after a rewarded ad. The
  destination is prepared first (next level built, or the map already underneath), then a 0.3 s curtain,
  then the ad; when it closes the destination is simply there.
- **Rewarded**: always a player-pressed button, always after a confirmation card that says what they
  get. Offline: the buttons are dimmed with an OFFLINE tag. Online but no fill (or no consent): the reward
  is free ("No ad available right now — the hint is free for this level"). The player is never punished.
  Every level can be finished without any rewarded ad
  (`LevelsAndCopyTests.testEveryCuratedLevelIsSolvableWithoutRewardedAds`).

## Remove Ads (StoreKit 2)

Banners disappear (slot collapses with a 0.25 s spring) and interstitials stop. Rewarded buttons stay
and grant the reward directly ("free, because you removed ads"). The entitlement is always re-read from
`Transaction.currentEntitlements`; a UserDefaults flag only avoids a first-frame flash.
