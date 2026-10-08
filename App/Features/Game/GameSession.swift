import BalanceCore
import BalancePhysics
import Observation
import OSLog
import SwiftUI
import UIKit

/// One attempt at one level: owns the scene and turns its events into game state for the views.
@MainActor
@Observable
final class GameSession: GameSceneDelegate {
    enum Phase: Equatable {
        /// Building + first quiet settle (0.5 s).
        case loading
        /// Rebuilding after undo/retry ("rewinding").
        case rewinding
        case playing
        /// A move's settle window is running; input locked, screen alive.
        case evaluating
        case collapsed
        case won
        case outOfMoves
    }

    enum Overlay: String, Identifiable {
        case pause, hint, hintNoAd
        var id: String { rawValue }
    }

    struct Hint: Equatable {
        var token: String
        var endsAt: Date
    }

    struct CollapseInfo {
        var recording: Recording
        var culpritId: String?
        var lostBalance: Bool
        var fromAnnotation: Bool
        var moveNumber: Int
    }

    private let log = Logger(subsystem: "Keystone", category: "game")
    let launch: GameLaunch
    let level: Level
    let tension: TensionIndex
    @ObservationIgnored let scene: GameScene
    @ObservationIgnored private unowned let app: AppModel

    private(set) var phase: Phase = .loading
    private(set) var moveLog = MoveLog()
    private(set) var selectedId: String?
    private(set) var tiers: [String: TensionTier] = [:]
    private(set) var hint: Hint?
    private(set) var revealCritical = false
    private(set) var usedHint = false
    private(set) var collapse: CollapseInfo?
    private(set) var collapsing = false
    private(set) var earnedStars = 0
    private(set) var completion: CompletionOutcome?
    private(set) var demo = false
    private(set) var tutorialVisible = false
    /// Bumped whenever piece frames may have moved (accessibility overlay).
    private(set) var layoutVersion = 0
    var overlay: Overlay? { didSet { scene.isPaused = overlay == .pause; if overlay == nil { scene.resetFrameClock() } } }

    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var evaluationContinuation: CheckedContinuation<EvaluationResult?, Never>?

    init(launch: GameLaunch, level: Level, app: AppModel, dark: Bool, reduceMotion: Bool) {
        self.launch = launch
        self.level = level
        self.app = app
        tension = TensionIndex(level: level)
        scene = GameScene(level: level, size: CGSize(width: 390, height: 600), palette: Palette.scene(dark: dark), reduceMotion: reduceMotion)
        scene.strings = SceneStrings(fitsHere: String(localized: "support.fits"), wontFit: String(localized: "support.invalid"),
                                     supportHere: String(localized: "support.here"))
        scene.gameDelegate = self
        if Copy.targetsNeedMarkers(level) && level.goal.type != .dropOnlyTarget {
            scene.markedTargets = Set(level.goal.targetPieceIds)
        }
        if !tension.isUsable, let reason = tension.mismatchReason {
            log.notice("\(level.id, privacy: .public): tension/hints off — \(reason, privacy: .public)")
        }
    }

    func dismissTutorial() { tutorialVisible = false }

    func start() {
        app.progress.recordAttempt(level.id)
        tutorialVisible = level.tutorial != nil && !app.progress.completedIds.contains(level.id)
        if level.tutorial == 1 { scene.tapTargetId = level.goal.targetPieceIds.first }
        phase = .loading
        scene.load(log: MoveLog())
    }

    // MARK: Derived

    var movesLeft: Int { level.goal.moveBudget - moveLog.count }
    var canUndo: Bool { !moveLog.isEmpty && (phase == .playing || phase == .outOfMoves || phase == .collapsed) && !demo }
    var supportsLeft: Int { max(0, level.supportsAllowed - moveLog.supportsPlaced) }
    var interactive: Bool { phase == .playing && overlay == nil && !demo }
    var isSettling: Bool { phase == .evaluating || phase == .loading || phase == .rewinding }

    var goalText: String { Copy.goalText(level) }
    var kicker: String { Copy.hudKicker(level, mode: launch.mode) }
    var progressText: String { Copy.goalProgress(level, removed: moveLog.removedIds) }

    // MARK: Moves

    private func removePiece(_ id: String) {
        guard phase == .playing else { return }
        let material = scene.structure?.piece(id)?.material ?? level.piece(id)?.material ?? .rope
        guard scene.apply(.remove(pieceId: id)) else { return }
        afterMove()
        app.sound.removed(material)
        app.haptics.pieceRemoved()
    }

    func placeSupport(_ placement: SupportPlacement) {
        guard phase == .playing, placement.isValid else { return }
        guard scene.apply(.placeSupport(position: placement.footPosition, rotation: placement.rotation)) else {
            rejectSupport()
            return
        }
        afterMove()
        app.sound.play(.place)
        app.haptics.pieceRemoved()
    }

    func rejectSupport() {
        app.haptics.nope()
        app.sound.play(.nope)
        app.showToast(String(localized: "support.toast.invalid"))
    }

    private func afterMove() {
        moveLog = scene.log
        selectedId = nil
        phase = .evaluating
        clearHint()
        tiers = [:]
        scene.setTiers([:])
        if level.tutorial == 1 { tutorialVisible = false; scene.tapTargetId = nil }
        if level.tutorial == 3 && moveLog.supportsPlaced > 0 { tutorialVisible = false }
        app.haptics.setSettling(true)
    }

    // MARK: GameSceneDelegate

    func gameSceneDidBecomeReady(_ scene: GameScene) {
        moveLog = scene.log
        phase = .playing
        refreshTiers(previous: [:])
        layoutVersion += 1
    }

    func gameScene(_ scene: GameScene, didSelect pieceId: String?) {
        selectedId = pieceId
        if pieceId != nil {
            app.haptics.select()
            app.sound.play(.select, volume: 0.5)
        }
        layoutVersion += 1
    }

    func gameScene(_ scene: GameScene, requestsRemovalOf pieceId: String) {
        removePiece(pieceId)
    }

    func gameScene(_ scene: GameScene, tappedLocked pieceId: String, reason: LockedReason) {
        app.haptics.nope()
        app.sound.play(.nope)
        switch reason {
        case .keystone: app.showToast(String(localized: "toast.keystone"))
        case .support: app.showToast(String(localized: "toast.support"))
        case .fixed, .notRemovable: app.showToast(String(localized: "toast.fixed"))
        }
    }

    func gameSceneCollapseBegan(_ scene: GameScene) {
        withAnimation(.easeOut(duration: 0.2)) { collapsing = true }
        let dropWin = level.goal.type == .dropOnlyTarget
        app.sound.play(dropWin ? .drop : .collapse)
        app.haptics.setSettling(false)
        app.haptics.collapse()
    }

    func gameScene(_ scene: GameScene, didFinish result: EvaluationResult) {
        app.haptics.setSettling(false)
        moveLog = scene.log
        if let c = evaluationContinuation {
            evaluationContinuation = nil
            c.resume(returning: result)
        }
        switch result.moveResult {
        case .continuePlaying:
            let previous = tiers
            phase = .playing
            collapsing = false
            refreshTiers(previous: previous)
        case .won:
            collapsing = false
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                self?.win()
            }
        case .outOfMoves:
            collapsing = false
            withAnimation(.easeOut(duration: 0.25)) { phase = .outOfMoves }
        case .collapsed:
            let token = result.move?.token ?? ""
            let annotated = tension.culprit(stateKey: result.stateKeyBefore, move: token)
            let culprit = annotated.flatMap { scene.structure?.piece($0) != nil || result.recording.ids.contains($0) ? $0 : nil }
                ?? result.heuristicCulprit
            var recording = result.recording
            recording.culprit = culprit
            let lostBalance: Bool = {
                guard let id = culprit, let m = result.metrics.first(where: { $0.id == id }) else { return true }
                return m.peakRotation >= PhysicsConstants.collapseRotation
            }()
            collapse = CollapseInfo(recording: recording, culpritId: culprit, lostBalance: lostBalance,
                                    fromAnnotation: annotated != nil, moveNumber: moveLog.count)
            if demo { return }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.3)) { self?.phase = .collapsed }
                self?.app.achievements.report(.firstCollapse)
            }
        }
        layoutVersion += 1
    }

    func gameSceneLayoutDidChange(_ scene: GameScene) {
        layoutVersion += 1
    }

    // MARK: Tension

    private func refreshTiers(previous: [String: TensionTier]) {
        guard tension.isUsable else { tiers = [:]; return }
        let new = tension.tiers(stateKey: moveLog.stateKey, revealCritical: revealCritical)
        tiers = new
        scene.setTiers(new)
        if new.contains(where: { id, t in t > (previous[id] ?? .none) && t >= .tense }) && !previous.isEmpty {
            app.haptics.crack()
        }
    }

    // MARK: Undo / retry

    func undo() {
        guard canUndo else { return }
        rebuild(log: moveLog.truncated(to: moveLog.count - 1))
        app.haptics.pieceRemoved()
        app.sound.play(.undo)
    }

    func retry() {
        demoTask?.cancel()
        demo = false
        revealCritical = false
        rebuild(log: MoveLog())
    }

    private func rebuild(log newLog: MoveLog) {
        clearHint()
        collapse = nil
        collapsing = false
        completion = nil
        overlay = nil
        phase = .rewinding
        moveLog = newLog
        scene.load(log: newLog)
    }

    // MARK: Hints (rewarded #1)

    func openHint() {
        guard phase == .playing, !demo else { return }
        if !app.ads.rewardedEnabled {
            app.showToast(String(localized: "hint.offline.toast"))
            return
        }
        overlay = app.ads.rewardedLikelyAvailable ? .hint : .hintNoAd
    }

    func watchHint() async {
        overlay = nil
        switch await app.ads.showRewarded() {
        case .earned, .free: applyHint()
        case .notEarned: app.showToast(String(localized: "hint.notEarned"))
        case .offline: app.showToast(String(localized: "hint.offline.toast"))
        }
    }

    func freeHint() {
        overlay = nil
        applyHint()
    }

    private func applyHint() {
        guard tension.isUsable else {
            app.showToast(String(localized: "hint.unavailable"))
            return
        }
        guard let token = tension.hint(stateKey: moveLog.stateKey, movesLeft: movesLeft) else {
            // Known state without a path = proven dead end; unknown state = no claim either way.
            let known = tension.entry(for: moveLog.stateKey) != nil
            app.showToast(String(localized: known ? "hint.noSolution" : "hint.offPath"))
            return
        }
        usedHint = true
        revealCritical = true
        refreshTiers(previous: tiers)
        showHint(token, seconds: 5)
    }

    private func showHint(_ token: String, seconds: Double) {
        hintTask?.cancel()
        hint = Hint(token: token, endsAt: .now.addingTimeInterval(seconds))
        scene.showHint(token)
        app.haptics.pieceRemoved()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.clearHint()
            self?.app.haptics.hintEnd()
        }
    }

    private func clearHint() {
        hintTask?.cancel()
        hint = nil
        scene.showHint(nil)
    }

    // MARK: Collapse → back to last move (rewarded #2)

    func backToLastMove() async {
        switch await app.ads.showRewarded() {
        case .earned, .free: undo()
        case .notEarned: break
        case .offline: app.showToast(String(localized: "hint.offline.toast"))
        }
    }

    // MARK: Win

    private func win() {
        guard phase != .won else { return }
        let moves = moveLog.count
        earnedStars = StarRules.stars(moves: moves, goal: level.goal)
        if !demo {
            let outcome = app.progress.recordCompletion(level.id, moves: moves, stars: earnedStars, usedHint: usedHint,
                                                         countsTowardStars: launch.isCampaign)
            completion = outcome
            app.ads.recordClear()
            if case let .daily(key) = launch.mode { app.progress.recordDailyCompletion(dayKey: key) }
            if launch.isEndless { app.noteEndlessCleared() }
            SharedSnapshotWriter.write(store: app.progress, catalog: app.catalog)
            app.achievements.evaluate(progress: app.progress, catalog: app.catalog, endlessCleared: app.endlessCleared)
        }
        let size = scene.standingExtent
        scene.showDimensions(widthLabel: String(format: "%.2f m", size.width), heightLabel: String(format: "%.2f m", size.height))
        withAnimation(.easeOut(duration: 0.35)) { phase = .won }
        demo = false
    }

    var bestMoves: Int { level.annotation?.solutionPath.count ?? level.goal.normalizedThresholds.first ?? level.goal.moveBudget }

    // MARK: Perfect solution (rewarded #3)

    func showPerfectSolution() async {
        guard let path = level.annotation?.solutionPath, tension.isUsable else {
            app.showToast(String(localized: "hint.unavailable"))
            return
        }
        switch await app.ads.showRewarded() {
        case .earned, .free: break
        case .notEarned: return
        case .offline: app.showToast(String(localized: "hint.offline.toast")); return
        }
        let keepStars = earnedStars
        retry()
        demo = true
        scene.inputEnabled = false
        demoTask = Task { [weak self] in
            guard let self else { return }
            while self.phase != .playing { try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { return } }
            try? await Task.sleep(for: .milliseconds(600))
            for token in path {
                guard !Task.isCancelled, self.demo else { return }
                self.showHint(token, seconds: 0.9)
                try? await Task.sleep(for: .milliseconds(850))
                let kind: Move.Kind
                if let s = SupportToken.parse(token) {
                    kind = .placeSupport(position: Vec2(s.x, self.level.resolvedFloorY), rotation: s.rotation)
                } else {
                    kind = .remove(pieceId: token)
                }
                self.clearHint()
                let result: EvaluationResult? = await withCheckedContinuation { c in
                    self.evaluationContinuation = c
                    if self.scene.apply(kind) {
                        self.afterMove()
                    } else {
                        self.evaluationContinuation = nil
                        c.resume(returning: nil)
                    }
                }
                guard let result else { self.demo = false; break }
                if result.moveResult == .won { break }
                if result.moveResult != .continuePlaying { self.demo = false; break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            self.scene.inputEnabled = true
            self.earnedStars = keepStars
        }
    }

    // MARK: Leaving

    enum Exit { case map, next }

    /// Exit from the end cards. Interstitials (§7.4) only ever happen here, after the destination
    /// is ready, behind a 0.3 s curtain.
    func leave(_ exit: Exit, swap: @escaping (GameLaunch?) -> Void) async {
        let fromEndCard = phase == .won || phase == .collapsed || phase == .outOfMoves
        let next = exit == .next ? nextLaunch() : nil
        if fromEndCard && app.ads.interstitialDue {
            withAnimation(.easeIn(duration: 0.3)) { app.curtain = true }
            try? await Task.sleep(for: .milliseconds(300))
            if let next { swap(next) }
            _ = await app.ads.showInterstitialIfDue()
            if next == nil { swap(nil) }
            withAnimation(.easeOut(duration: 0.3)) { app.curtain = false }
        } else {
            swap(next)
        }
    }

    private func nextLaunch() -> GameLaunch? {
        switch launch.mode {
        case .campaign:
            guard let next = app.catalog.next(after: level.id), app.isLevelUnlocked(next.id) else { return nil }
            return GameLaunch(levelId: next.id, mode: .campaign)
        case .daily:
            return nil
        case .endless:
            guard let next = app.endlessLevel() else { return nil }
            return GameLaunch(levelId: next.id, mode: .endless(number: app.endlessNumber))
        }
    }

    var hasNext: Bool {
        switch launch.mode {
        case .campaign: return app.catalog.next(after: level.id).map { app.isLevelUnlocked($0.id) } ?? false
        case .daily: return false
        case .endless: return true
        }
    }

    func teardown() {
        hintTask?.cancel()
        demoTask?.cancel()
        app.haptics.setSettling(false)
        scene.isPaused = true
        scene.gameDelegate = nil
    }

    // MARK: Accessibility

    func accessibilityLabel(for id: String) -> String? {
        guard let piece = scene.structure?.piece(id) else { return nil }
        return Copy.pieceAccessibility(piece, tier: tiers[id] ?? .none, removable: scene.isRemovable(id),
                                       selected: selectedId == id, target: level.goal.targetPieceIds.contains(id))
    }
}
