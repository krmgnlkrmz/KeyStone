import GoogleMobileAds
import OSLog
import UIKit

/// Preloads one interstitial and presents it on request. Ad objects never leave the main actor.
@MainActor
final class InterstitialController: NSObject, FullScreenContentDelegate {
    private let log = Logger(subsystem: "Keystone", category: "ads")
    private var ad: InterstitialAd?
    private var loading = false
    private var dismissal: CheckedContinuation<Void, Never>?

    var isReady: Bool { ad != nil }

    func preload() {
        guard ad == nil, !loading else { return }
        loading = true
        InterstitialAd.load(with: AppConfig.AdUnit.interstitial, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            self.loading = false
            if let error { self.log.info("interstitial not loaded: \(error.localizedDescription)"); return }
            ad?.fullScreenContentDelegate = self
            self.ad = ad
        }
    }

    /// Presents and waits until it is dismissed. Returns false when nothing was loaded.
    func present(from viewController: UIViewController) async -> Bool {
        guard let ad else { preload(); return false }
        self.ad = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dismissal = continuation
            ad.present(from: viewController)
        }
        preload()
        return true
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        dismissal?.resume()
        dismissal = nil
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        log.error("interstitial failed to present: \(error.localizedDescription)")
        dismissal?.resume()
        dismissal = nil
    }
}
