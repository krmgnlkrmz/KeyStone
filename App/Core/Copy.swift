import BalanceCore
import Foundation

/// Builds user-facing sentences from level data. Every string comes from Localizable.xcstrings.
enum Copy {
    /// The app's resolved UI language ("en" or "tr").
    static var language: String { Bundle.main.preferredLocalizations.first ?? "en" }

    static func regionName(_ region: Region) -> String {
        switch region {
        case .woodScaffold: return String(localized: "zone.woodScaffold")
        case .stoneArch: return String(localized: "zone.stoneArch")
        case .ironTruss: return String(localized: "zone.ironTruss")
        case .ropeBridge: return String(localized: "zone.ropeBridge")
        case .steelCrane: return String(localized: "zone.steelCrane")
        case .counterweight: return String(localized: "zone.counterweight")
        case .keystone: return String(localized: "zone.keystone")
        }
    }

    /// "01 · WOODEN SCAFFOLD"
    static func zoneTitle(_ region: Region) -> String {
        let n = region.order + 1
        return "\(n < 10 ? "0" : "")\(n) · \(regionName(region).uppercased(with: Locale.current))"
    }

    static func levelName(_ level: Level) -> String {
        level.localizedName(language: language) ?? String(localized: "level.untitled")
    }

    /// Menu card / pause sheet title: "Level 12 · Pinned Lintel".
    static func levelTitle(_ level: Level, mode: GameLaunch.Mode) -> String {
        switch mode {
        case .campaign: return String(localized: "level.title \(level.index) \(levelName(level))")
        case .daily: return String(localized: "daily.title")
        case let .endless(n): return String(localized: "endless.levelTitle \(n)")
        }
    }

    /// HUD mono kicker: "LEVEL 12", "DAILY · OCT 8", "ENDLESS · 214".
    static func hudKicker(_ level: Level, mode: GameLaunch.Mode) -> String {
        switch mode {
        case .campaign:
            return String(localized: "hud.level \(level.index)")
        case let .daily(key):
            return String(localized: "hud.daily \(shortDate(key))").uppercased(with: Locale.current)
        case let .endless(n):
            return String(localized: "hud.endless \(n)")
        }
    }

    /// "Level 12" / "Daily" / "Endless"
    static func shortLevel(_ level: Level, mode: GameLaunch.Mode) -> String {
        switch mode {
        case .campaign: return String(localized: "level.short \(level.index)")
        case .daily: return String(localized: "daily.short")
        case .endless: return String(localized: "endless.title")
        }
    }

    static func date(forKey key: String) -> Date? {
        guard let n = DailyLevelPicker.dayNumber(key) else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c.date(from: DateComponents(year: 1970, month: 1, day: 1 + n, hour: 12))
    }

    /// "Oct 8"
    static func shortDate(_ key: String) -> String {
        date(forKey: key)?.formatted(.dateTime.month(.abbreviated).day()) ?? key
    }

    /// "THU · OCT 8, 2026"
    static func longDate(_ key: String) -> String {
        guard let d = date(forKey: key) else { return key }
        let weekday = d.formatted(.dateTime.weekday(.abbreviated))
        let rest = d.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(weekday) · \(rest)".uppercased(with: Locale.current)
    }

    // MARK: Goal

    static func noun(_ n: PieceNoun) -> String {
        switch n {
        case .post: return String(localized: "noun.post")
        case .beam: return String(localized: "noun.beam")
        case .block: return String(localized: "noun.block")
        case .column: return String(localized: "noun.column")
        case .girder: return String(localized: "noun.girder")
        case .keystone: return String(localized: "noun.keystone")
        case .support: return String(localized: "noun.support")
        case .rope: return String(localized: "noun.rope")
        case .piece: return String(localized: "noun.piece")
        }
    }

    /// Shared noun of the goal targets, or `.piece` when they differ.
    static func targetNoun(_ level: Level) -> PieceNoun {
        let nouns = Set(level.goal.targetPieceIds.map { id -> PieceNoun in
            if let p = level.piece(id) { return PieceNaming.noun(for: p) }
            return level.joints.contains { $0.id == id } ? .rope : .piece
        })
        return nouns.count == 1 ? nouns.first! : .piece
    }

    /// True when the goal names a noun that other non-target pieces share — the scene marks targets then.
    static func targetsNeedMarkers(_ level: Level) -> Bool {
        let noun = targetNoun(level)
        let targets = Set(level.goal.targetPieceIds)
        if noun == .piece { return true }
        return level.pieces.contains { !targets.contains($0.id) && PieceNaming.noun(for: $0) == noun }
    }

    static func goalText(_ level: Level) -> String {
        if let custom = level.localizedGoalText(language: language) { return custom }
        let n = level.goal.effectiveRequiredCount
        let noun = targetNoun(level)
        let text: String
        switch level.goal.type {
        case .dropOnlyTarget:
            text = String(localized: "goal.drop \(object(noun, count: 1))")
        case .placeSupportThenRemove:
            text = String(localized: "goal.support \(n) \(object(noun, count: n))")
        case .removeTargetsKeepStanding:
            if n == 1 && level.goal.targetPieceIds.count == 1 {
                text = String(localized: "goal.removeOne \(object(noun, count: 1))")
            } else {
                text = String(localized: "goal.remove \(n) \(object(noun, count: n))")
            }
        }
        return capitalizedFirst(text)
    }

    /// The noun as the object of "remove"/"drop": EN singular/plural, TR accusative ("direği").
    static func object(_ n: PieceNoun, count: Int) -> String {
        let many = count != 1
        switch n {
        case .post: return many ? String(localized: "noun.post.objectMany") : String(localized: "noun.post.objectOne")
        case .beam: return many ? String(localized: "noun.beam.objectMany") : String(localized: "noun.beam.objectOne")
        case .block: return many ? String(localized: "noun.block.objectMany") : String(localized: "noun.block.objectOne")
        case .column: return many ? String(localized: "noun.column.objectMany") : String(localized: "noun.column.objectOne")
        case .girder: return many ? String(localized: "noun.girder.objectMany") : String(localized: "noun.girder.objectOne")
        case .keystone: return many ? String(localized: "noun.keystone.objectMany") : String(localized: "noun.keystone.objectOne")
        case .support: return many ? String(localized: "noun.support.objectMany") : String(localized: "noun.support.objectOne")
        case .rope: return many ? String(localized: "noun.rope.objectMany") : String(localized: "noun.rope.objectOne")
        case .piece: return many ? String(localized: "noun.piece.objectMany") : String(localized: "noun.piece.objectOne")
        }
    }

    /// Turkish templates may start with the object ("direği sök"); capitalise the sentence.
    static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased(with: Locale(identifier: language)) + s.dropFirst()
    }

    /// HUD progress caption: "1/3 DONE" or "MOVES".
    static func goalProgress(_ level: Level, removed: Set<String>) -> String {
        guard level.goal.type != .dropOnlyTarget else { return String(localized: "hud.moves") }
        let done = GoalRules.removedTargetCount(goal: level.goal, removed: removed)
        return String(localized: "hud.done \(min(done, level.goal.effectiveRequiredCount)) \(level.goal.effectiveRequiredCount)")
    }

    // MARK: Collapse

    static func blame(_ piece: Piece, lostBalance: Bool) -> String {
        let n = noun(PieceNaming.noun(for: piece))
        return lostBalance ? String(localized: "collapse.label.balance \(n)") : String(localized: "collapse.label.load \(n)")
    }

    // MARK: Accessibility

    /// "Support spot 2 of 3, under the beam".
    static func supportSpot(_ spot: SupportPlacement, index: Int, of count: Int, level: Level) -> String {
        let under = spot.targetId.flatMap { level.piece($0) }.map { noun(PieceNaming.noun(for: $0)) } ?? noun(.piece)
        return String(localized: "a11y.supportSpot \(index + 1) \(count) \(under)")
    }

    static func material(_ m: Material) -> String {
        switch m {
        case .wood: return String(localized: "material.wood")
        case .stone: return String(localized: "material.stone")
        case .steel: return String(localized: "material.steel")
        case .brass: return String(localized: "material.brass")
        case .rope: return String(localized: "material.rope")
        }
    }

    static func tier(_ t: TensionTier) -> String? {
        switch t {
        case .none: return nil
        case .light: return String(localized: "tension.light")
        case .tense: return String(localized: "tension.tense")
        case .critical: return String(localized: "tension.critical")
        }
    }

    /// "wood beam, under load, removable"
    static func pieceAccessibility(_ piece: Piece, tier: TensionTier, removable: Bool, selected: Bool, target: Bool) -> String {
        var parts = ["\(material(piece.material)) \(noun(PieceNaming.noun(for: piece)))"]
        if let t = self.tier(tier) { parts.append(t) }
        if target { parts.append(String(localized: "a11y.target")) }
        parts.append(removable ? String(localized: "a11y.removable") : (piece.fixed ? String(localized: "a11y.fixed") : String(localized: "a11y.notRemovable")))
        if selected { parts.append(String(localized: "a11y.selected")) }
        return parts.joined(separator: ", ")
    }

    static func ropeAccessibility(tier: TensionTier, removable: Bool, selected: Bool, target: Bool) -> String {
        var parts = [noun(.rope)]
        if let t = self.tier(tier) { parts.append(t) }
        if target { parts.append(String(localized: "a11y.target")) }
        parts.append(removable ? String(localized: "a11y.removable") : String(localized: "a11y.notRemovable"))
        if selected { parts.append(String(localized: "a11y.selected")) }
        return parts.joined(separator: ", ")
    }
}
