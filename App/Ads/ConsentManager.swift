import OSLog
import UIKit
import UserMessagingPlatform

/// Google UMP. Consent is gathered before anything ad-related starts (§7.3).
///
/// UMP's completion-based calls are made from the main actor inside `withCheckedContinuation`,
/// so the SDK is always entered on the main thread.
@MainActor
final class ConsentManager {
    private let log = Logger(subsystem: "Keystone", category: "consent")

    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }

    /// Google's rule: show the "Privacy settings" entry point only when UMP says it is required.
    var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// 1. Refresh consent info. Errors (offline) are logged and swallowed: the game never waits on ads.
    func requestConsentInfoUpdate() async -> Bool {
        let parameters = RequestParameters()
        #if DEBUG
        if ProcessInfo.processInfo.environment["UMP_DEBUG_EEA"] == "1" {
            let debug = DebugSettings()
            debug.geography = .EEA
            parameters.debugSettings = debug
        }
        #endif
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [log] error in
                if let error { log.error("consent info update failed: \(error.localizedDescription)") }
                continuation.resume(returning: error == nil)
            }
        }
    }

    /// 2. Loads and shows the form only when UMP requires it.
    func loadAndPresentIfRequired(from viewController: UIViewController?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ConsentForm.loadAndPresentIfRequired(from: viewController) { [log] error in
                if let error { log.error("consent form failed: \(error.localizedDescription)") }
                continuation.resume()
            }
        }
    }

    /// Settings → Privacy settings.
    func presentPrivacyOptions(from viewController: UIViewController?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ConsentForm.presentPrivacyOptionsForm(from: viewController) { [log] error in
                if let error { log.error("privacy options failed: \(error.localizedDescription)") }
                continuation.resume()
            }
        }
    }
}
