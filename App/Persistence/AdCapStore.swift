import BalanceCore
import Foundation

/// Interstitial pacing counters (§7.4) persisted in UserDefaults.
@MainActor
final class AdCapStore {
    private let defaults: UserDefaults
    private let key = "ads.frequencyCap.v1"
    private let cap = AdFrequencyCap()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var state: AdFrequencyCap.State {
        get {
            guard let data = defaults.data(forKey: key),
                  let s = try? JSONDecoder().decode(AdFrequencyCap.State.self, from: data) else { return .init() }
            return s
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    func recordClear() { state = cap.recordingClear(state) }
    func recordInterstitial(at now: Date = .now) { state = cap.recordingInterstitial(state, at: now) }
    func recordRewarded(at now: Date = .now) { state = cap.recordingRewarded(state, at: now) }
    func shouldShowInterstitial(now: Date = .now, adsRemoved: Bool) -> Bool {
        cap.shouldShowInterstitial(state: state, now: now, adsRemoved: adsRemoved)
    }
    func reset() { defaults.removeObject(forKey: key) }
}
