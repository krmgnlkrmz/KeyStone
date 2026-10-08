import Foundation

/// UI-only cache of the Remove Ads entitlement so the first frame doesn't flash a banner slot.
/// The truth is always `Transaction.currentEntitlements`, re-checked at every launch.
enum EntitlementCache {
    private static let key = "store.removeAds.cached"
    static var removeAds: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
