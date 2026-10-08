import GoogleMobileAds
import OSLog
import UIKit

/// Preloads one rewarded ad. The reward is reported only when the SDK says it was earned.
@MainActor
final class RewardedController: NSObject, FullScreenContentDelegate {
    private let log = Logger(subsystem: "Keystone", category: "ads")
    private var ad: RewardedAd?
    private var loading = false
    private var earned = false
    private var dismissal: CheckedContinuation<Bool, Never>?

    var isReady: Bool { ad != nil }
    var isLoading: Bool { loading }

    func preload() {
        guard ad == nil, !loading else { return }
        loading = true
        Task {
            let loaded = await load()
            loading = false
            loaded?.fullScreenContentDelegate = self
            ad = loaded
        }
    }

    private func load() async -> RewardedAd? {
        await withCheckedContinuation { (continuation: CheckedContinuation<RewardedAd?, Never>) in
            RewardedAd.load(with: AppConfig.AdUnit.rewarded, request: Request()) { [log] ad, error in
                if let error { log.info("rewarded not loaded: \(error.localizedDescription)") }
                continuation.resume(returning: ad)
            }
        }
    }

    /// Waits a moment for an in-flight load (the confirmation card gives us that time).
    func waitUntilLoaded(timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ad == nil && loading && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
        return ad != nil
    }

    /// Presents and returns whether the reward was earned.
    func present(from viewController: UIViewController) async -> Bool {
        guard let ad else { preload(); return false }
        self.ad = nil
        earned = false
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            dismissal = continuation
            ad.present(from: viewController) { [weak self] in
                self?.earned = true
            }
        }
        preload()
        return result
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        dismissal?.resume(returning: earned)
        dismissal = nil
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        log.error("rewarded failed to present: \(error.localizedDescription)")
        dismissal?.resume(returning: false)
        dismissal = nil
    }
}
