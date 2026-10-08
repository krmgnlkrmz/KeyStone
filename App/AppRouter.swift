import BalanceCore
import Foundation
import Observation

/// Push destinations inside the root NavigationStack. No TabView anywhere.
enum Route: Hashable {
    case map
    case endless
}

/// Sheets that can appear over the menu/map. Settings is a sheet everywhere (one pattern).
enum SheetRoute: String, Identifiable {
    case settings, daily
    var id: String { rawValue }
}

/// A level being played in the full-screen game cover.
struct GameLaunch: Identifiable, Hashable {
    enum Mode: Hashable {
        case campaign
        case daily(dayKey: String)
        case endless(number: Int)
    }

    let id = UUID()
    let levelId: String
    let mode: Mode

    var isCampaign: Bool { if case .campaign = mode { return true }; return false }
    var isDaily: Bool { if case .daily = mode { return true }; return false }
    var isEndless: Bool { if case .endless = mode { return true }; return false }
}

@MainActor
@Observable
final class AppRouter {
    var path: [Route] = []
    var sheet: SheetRoute?
    /// The game is a fullScreenCover (no accidental swipe-back); exit only through Pause or the end cards.
    var game: GameLaunch?

    func popToRoot() { path.removeAll() }
}
