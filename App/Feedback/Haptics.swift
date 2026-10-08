import CoreHaptics
import UIKit

/// The haptic table from the design system. Every call is a no-op when Haptics is off.
@MainActor
final class Haptics {
    var enabled = true
    private var engine: CHHapticEngine?
    private var settlePlayer: CHHapticAdvancedPatternPlayer?
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    /// Piece touch-down, valid support snap, scrub markers.
    func select() { guard enabled else { return }; selection.selectionChanged() }
    /// Piece removed, undo, hint start.
    func pieceRemoved() { guard enabled else { return }; light.impactOccurred() }
    /// Invalid placement or locked piece: soft, not an error buzz.
    func nope() { guard enabled else { return }; soft.impactOccurred(intensity: 0.4) }
    /// A crack appears (tier goes up).
    func crack() { guard enabled else { return }; rigid.impactOccurred(intensity: 0.6) }
    /// One per star on Level Clear.
    func star() { guard enabled else { return }; notify.notificationOccurred(.success) }
    /// Hint ring ends.
    func hintEnd() { guard enabled else { return }; soft.impactOccurred(intensity: 0.5) }

    /// Collapse: transient 1.0 / 0.7, then 0.35 s decaying rumble.
    func collapse() {
        guard enabled else { return }
        guard let engine else { rigid.impactOccurred(intensity: 1); return }
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ], relativeTime: 0.05, duration: 0.35),
        ]
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0.05, value: 1), .init(relativeTime: 0.4, value: 0),
        ], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: events, parameterCurves: [curve]),
           let player = try? engine.makePlayer(with: pattern) {
            try? engine.start()
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    /// While the structure settles and sways: a faint continuous texture (intensity 0.15, sharpness 0.1).
    func setSettling(_ on: Bool) {
        guard let engine else { return }
        if on, enabled {
            guard settlePlayer == nil else { return }
            let e = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
            ], relativeTime: 0, duration: 2.5)
            if let pattern = try? CHHapticPattern(events: [e], parameters: []),
               let player = try? engine.makeAdvancedPlayer(with: pattern) {
                try? engine.start()
                try? player.start(atTime: CHHapticTimeImmediate)
                settlePlayer = player
            }
        } else {
            try? settlePlayer?.stop(atTime: CHHapticTimeImmediate)
            settlePlayer = nil
        }
    }
}
