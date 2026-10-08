import BalanceCore
import Foundation
import GoogleMobileAds
import Network
import Observation
import OSLog
import UIKit

/// What a rewarded button delivers.
enum RewardOutcome: Equatable {
    /// The ad played to the end.
    case earned
    /// No ad to show (no fill, no consent) or Remove Ads owned: the reward is free.
    case free
    /// The player closed the ad early.
    case notEarned
    /// Offline: rewarded buttons are disabled, nothing happens.
    case offline
}

/// Single entry point for everything ad-related (§7). Policy lives in docs/ads-policy.md:
/// no ads at launch, in the game or in the collapse replay; interstitials only on Result → Map/Next.
@MainActor
@Observable
final class AdsCoordinator {
    private let log = Logger(subsystem: "Keystone", category: "ads")
    @ObservationIgnored let consent = ConsentManager()
    @ObservationIgnored let interstitials = InterstitialController()
    @ObservationIgnored let rewardeds = RewardedController()
    @ObservationIgnored let cap = AdCapStore()
    @ObservationIgnored private let monitor = NWPathMonitor()

    /// `MobileAds.start()` has been called (only ever after consent allows it).
    private(set) var started = false
    private(set) var canRequestAds = false
    private(set) var privacyOptionsRequired = false
    private(set) var isOnline = true
    /// Mirrors the Remove Ads entitlement.
    var adsRemoved = false

    init() {
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "keystone.network"))
    }

    /// Rewarded buttons are disabled only when offline (never because of a missing fill).
    var rewardedEnabled: Bool { isOnline || adsRemoved }

    // MARK: Launch sequence (§7.3)

    /// 1–2: UMP info update and form. Never blocks the game on errors.
    func gatherConsent() async {
        _ = await consent.requestConsentInfoUpdate()
        await consent.loadAndPresentIfRequired(from: UIApplication.topViewController)
        canRequestAds = consent.canRequestAds
        privacyOptionsRequired = consent.isPrivacyOptionsRequired
    }

    /// 5–6: the only place `MobileAds.start()` is called.
    func startIfAllowed() async {
        canRequestAds = consent.canRequestAds
        guard canRequestAds, !started else {
            if !canRequestAds { log.info("MobileAds.start skipped: consent does not allow ads") }
            return
        }
        log.info("MobileAds.start after consent")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { @Sendable _ in continuation.resume() }
        }
        started = true
        preload()
    }

    func preload() {
        guard started else { return }
        if !adsRemoved { interstitials.preload() }
        rewardeds.preload()
    }

    func presentPrivacyOptions() async {
        await consent.presentPrivacyOptions(from: UIApplication.topViewController)
        canRequestAds = consent.canRequestAds
        privacyOptionsRequired = consent.isPrivacyOptionsRequired
        if canRequestAds { await startIfAllowed() }
    }

    // MARK: Interstitial

    /// Called only on Result → Map / Next, after the destination is prepared.
    /// Returns true when an interstitial was shown.
    func showInterstitialIfDue() async -> Bool {
        guard started, !adsRemoved, cap.shouldShowInterstitial(adsRemoved: adsRemoved),
              interstitials.isReady, let vc = UIApplication.topViewController else { return false }
        cap.recordInterstitial()
        return await interstitials.present(from: vc)
    }

    var interstitialDue: Bool {
        started && !adsRemoved && interstitials.isReady && cap.shouldShowInterstitial(adsRemoved: adsRemoved)
    }

    func recordClear() { cap.recordClear() }

    // MARK: Rewarded

    /// Plays a rewarded ad after the player confirmed on the card. The player is never punished:
    /// no fill or no consent makes the reward free; Remove Ads makes it free ("thanks for buying").
    func showRewarded() async -> RewardOutcome {
        if adsRemoved { return .free }
        guard isOnline else { return .offline }
        guard started else { return .free }
        if !rewardeds.isReady { rewardeds.preload() }
        guard await rewardeds.waitUntilLoaded(), let vc = UIApplication.topViewController else { return .free }
        let earned = await rewardeds.present(from: vc)
        if earned { cap.recordRewarded() }
        return earned ? .earned : .notEarned
    }

    /// Whether a fill is likely right now (drives "No ad available right now" vs "Watch Ad").
    var rewardedLikelyAvailable: Bool { adsRemoved || (started && (rewardeds.isReady || rewardeds.isLoading)) }
}

extension UIApplication {
    /// Topmost presented view controller of the key window, for SDKs that present modally.
    @MainActor
    static var topViewController: UIViewController? {
        let scenes = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
