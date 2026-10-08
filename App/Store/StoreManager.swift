import Foundation
import Observation
import OSLog
import StoreKit

/// StoreKit 2, one non-consumable: Remove Ads. Price always comes from StoreKit (`displayPrice`).
@MainActor
@Observable
final class StoreManager {
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        /// Ask to Buy / SCA: ads stay on until approved.
        case pending
        case failed
    }

    private let log = Logger(subsystem: "Keystone", category: "store")
    private(set) var product: Product?
    private(set) var adsRemoved: Bool
    private(set) var state: PurchaseState = .idle
    private(set) var restoring = false
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// Called whenever the entitlement changes (AdsCoordinator mirrors it).
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    init() {
        adsRemoved = EntitlementCache.removeAds
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    var productID: String { AppConfig.removeAdsProductID }
    var displayPrice: String? { product?.displayPrice }

    func load() async {
        do {
            product = try await Product.products(for: [productID]).first
        } catch {
            log.error("products failed: \(error.localizedDescription)")
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(t) = result, t.productID == productID, t.revocationDate == nil {
                owned = true
            }
        }
        set(owned)
        if owned, state == .pending { state = .idle }
    }

    private func set(_ owned: Bool) {
        guard owned != adsRemoved else { return }
        adsRemoved = owned
        EntitlementCache.removeAds = owned
        onChange?(owned)
    }

    func purchase() async {
        if product == nil { await load() }
        guard let product, state != .purchasing else { return }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case let .success(verification):
                if case let .verified(t) = verification {
                    await t.finish()
                    set(true)
                    state = .idle
                } else {
                    state = .failed
                }
            case .pending:
                state = .pending
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            log.error("purchase failed: \(error.localizedDescription)")
            state = .failed
        }
    }

    /// "Restore Purchases": syncs with the App Store, then re-reads entitlements.
    @discardableResult
    func restore() async -> Bool {
        restoring = true
        defer { restoring = false }
        do { try await AppStore.sync() } catch { log.error("sync failed: \(error.localizedDescription)") }
        await refreshEntitlements()
        return adsRemoved
    }

    func clearFailure() { if state == .failed { state = .idle } }
}
