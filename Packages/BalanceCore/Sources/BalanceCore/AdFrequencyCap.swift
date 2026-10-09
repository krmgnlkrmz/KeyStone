import Foundation

/// Interstitial pacing. Pure logic so every rule in docs/ads-policy.md is unit-tested.
///
/// - Nothing during the first `graceLevels` clears (the tutorial).
/// - After that, at least `levelInterval` clears between two interstitials,
/// - at least `minSecondsBetween` seconds between two interstitials,
/// - at least `minSecondsAfterRewarded` seconds after a rewarded ad,
/// - never once Remove Ads is owned.
///
/// The caller decides *where* (only on Result → Map/Next); this type decides *whether*.
public struct AdFrequencyCap: Sendable {
    public static let levelInterval = 3
    public static let minSecondsBetween: TimeInterval = 90
    public static let graceLevels = 3
    public static let minSecondsAfterRewarded: TimeInterval = 45

    public struct State: Codable, Sendable, Equatable {
        /// Lifetime level clears (replays count).
        public var completedLevels: Int
        /// Clears after the grace period since the last interstitial.
        public var clearsSinceLastInterstitial: Int
        public var lastInterstitialAt: Date?
        public var lastRewardedAt: Date?

        public init(completedLevels: Int = 0, clearsSinceLastInterstitial: Int = 0,
                    lastInterstitialAt: Date? = nil, lastRewardedAt: Date? = nil) {
            self.completedLevels = completedLevels
            self.clearsSinceLastInterstitial = clearsSinceLastInterstitial
            self.lastInterstitialAt = lastInterstitialAt
            self.lastRewardedAt = lastRewardedAt
        }
    }

    public init() {}

    public func shouldShowInterstitial(state: State, now: Date, adsRemoved: Bool = false) -> Bool {
        if adsRemoved { return false }
        if state.completedLevels <= Self.graceLevels { return false }
        if state.clearsSinceLastInterstitial < Self.levelInterval { return false }
        if let last = state.lastInterstitialAt, now.timeIntervalSince(last) < Self.minSecondsBetween { return false }
        if let rewarded = state.lastRewardedAt, now.timeIntervalSince(rewarded) < Self.minSecondsAfterRewarded { return false }
        return true
    }

    public func recordingClear(_ state: State) -> State {
        var s = state
        s.completedLevels += 1
        if s.completedLevels > Self.graceLevels { s.clearsSinceLastInterstitial += 1 }
        return s
    }

    public func recordingInterstitial(_ state: State, at now: Date) -> State {
        var s = state
        s.clearsSinceLastInterstitial = 0
        s.lastInterstitialAt = now
        return s
    }

    public func recordingRewarded(_ state: State, at now: Date) -> State {
        var s = state
        s.lastRewardedAt = now
        return s
    }
}
