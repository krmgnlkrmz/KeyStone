import Foundation
import SwiftData

/// One row: the player's settings, streak and endless position. Stays on this device.
@Model
final class PlayerState {
    var lastPlayedLevelId: String?
    var totalStars: Int = 0
    var dailyStreak: Int = 0
    var lastDailyCompleted: Date?
    /// Local `yyyy-MM-dd` of the last solved daily (the streak works on day keys, not instants).
    var lastDailyCompletedKey: String?
    /// Recent solved daily keys, newest last (week strip in the Daily sheet).
    var dailyCompletedKeys: [String] = []
    var soundEnabled: Bool = true
    var musicEnabled: Bool = false
    var hapticsEnabled: Bool = true
    var leftHandedHUD: Bool = false
    /// Position in the player's endless permutation.
    var endlessCursor: Int = 0
    /// Seeds the player's endless permutation (stored as Int64 bit pattern).
    var endlessSeed: Int64 = 0
    var totalClears: Int = 0
    var clearsWithoutHint: Int = 0
    var onboardingCompleted: Bool = false
    var tutorialsSkipped: Bool = false

    init() {
        endlessSeed = Int64.random(in: Int64.min...Int64.max)
    }
}
