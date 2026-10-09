import Foundation

/// Today's level without a server: the local calendar day picks a level from a fixed candidate list.
///
/// Every device with the same app version shows the same level on the same calendar day. Within one
/// pass over the candidate list no level repeats (a multiplicative walk with a stride coprime to N).
public enum DailyLevelPicker {
    private static let salt = "keystone-daily-v1"

    /// `yyyy-MM-dd` in the calendar's time zone (the player's local day).
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return format(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    static func format(year: Int, month: Int, day: Int) -> String {
        func pad(_ v: Int, _ width: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// Days since 1970-01-01 for a `yyyy-MM-dd` key, using the proleptic Gregorian calendar.
    public static func dayNumber(_ key: String) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return daysFromCivil(year: parts[0], month: parts[1], day: parts[2])
    }

    public static func key(forDayNumber n: Int) -> String {
        let (y, m, d) = civilFromDays(n)
        return format(year: y, month: m, day: d)
    }

    /// Picks one id for the day. `candidates` order does not matter; it is sorted first.
    public static func pick(dayKey: String, candidates: [String]) -> String? {
        let pool = candidates.sorted()
        guard !pool.isEmpty, let day = dayNumber(dayKey) else { return pool.first }
        let n = pool.count
        let offset = Int(StableHash.fnv1a64(salt) % UInt64(n))
        let stride = coprimeStride(for: n)
        let index = ((day % n + n) % n * stride + offset) % n
        return pool[index]
    }

    public static func pick(date: Date, calendar: Calendar = .current, candidates: [String]) -> String? {
        pick(dayKey: dayKey(for: date, calendar: calendar), candidates: candidates)
    }

    /// A stride close to n·φ that shares no factor with n, so consecutive days land far apart.
    static func coprimeStride(for n: Int) -> Int {
        guard n > 2 else { return 1 }
        var s = max(1, Int(Double(n) * 0.618_033_988_7))
        while gcd(s, n) != 1 { s += 1 }
        return s % n == 0 ? 1 : s
    }

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

    // Howard Hinnant's days_from_civil / civil_from_days.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

/// Daily streak bookkeeping, all on `yyyy-MM-dd` keys so time zones and DST never matter.
public enum StreakRules {
    /// Streak after solving `dayKey`'s daily level.
    public static func streakAfterCompleting(dayKey: String, lastCompletedKey: String?, streak: Int) -> Int {
        guard let today = DailyLevelPicker.dayNumber(dayKey) else { return streak }
        guard let lastKey = lastCompletedKey, let last = DailyLevelPicker.dayNumber(lastKey) else { return 1 }
        switch today - last {
        case 0: return max(streak, 1)
        case 1: return streak + 1
        case ..<0: return streak // solving an older day never changes the streak
        default: return 1
        }
    }

    /// The streak to show today: still alive if the last solve was today or yesterday.
    public static func displayStreak(todayKey: String, lastCompletedKey: String?, streak: Int) -> Int {
        guard let today = DailyLevelPicker.dayNumber(todayKey),
              let lastKey = lastCompletedKey, let last = DailyLevelPicker.dayNumber(lastKey) else { return 0 }
        return (0...1).contains(today - last) ? streak : 0
    }

    public static func isSolved(todayKey: String, lastCompletedKey: String?) -> Bool {
        todayKey == lastCompletedKey
    }

    /// Monday-first week containing `todayKey`, as day keys.
    public static func weekKeys(containing todayKey: String) -> [String] {
        guard let today = DailyLevelPicker.dayNumber(todayKey) else { return [] }
        // 1970-01-01 was a Thursday → weekday index with Monday = 0.
        let weekday = ((today % 7) + 7 + 3) % 7
        let monday = today - weekday
        return (0..<7).map { DailyLevelPicker.key(forDayNumber: monday + $0) }
    }
}
