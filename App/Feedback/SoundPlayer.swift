import AVFoundation
import BalanceCore
import OSLog

/// Short effects from Resources/Sounds plus the optional ambient bed (music), ducked in the game.
@MainActor
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case tick, select, place, nope, collapse, drop, chime, creak, scrape, ring, undo
    }

    var effectsEnabled = true
    var musicEnabled = false { didSet { updateMusic() } }
    /// The game screen ducks the bed to near-silence.
    var ducked = false { didSet { music?.setVolume(ducked ? 0.04 : 0.35, fadeDuration: 0.4) } }

    private var players: [Effect: [AVAudioPlayer]] = [:]
    private var music: AVAudioPlayer?
    private let log = Logger(subsystem: "Keystone", category: "audio")

    private var sessionReady = false

    /// Nothing here runs on the cold-start path: the session and the players are made by `warmUp()`
    /// once the menu is up (22 prepared AVAudioPlayers on the main thread), or on the first sound.
    init() {}

    func warmUp() {
        for e in Effect.allCases where players[e] == nil { players[e] = makePlayers(e) }
    }

    private func ensureSession() {
        guard !sessionReady else { return }
        sessionReady = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    private func makePlayers(_ e: Effect) -> [AVAudioPlayer] {
        ensureSession()
        guard let url = Bundle.main.url(forResource: e.rawValue, withExtension: "caf", subdirectory: nil)
                ?? Bundle.main.url(forResource: e.rawValue, withExtension: "wav") else { return [] }
        return (0..<2).compactMap { _ in
            let p = try? AVAudioPlayer(contentsOf: url)
            p?.prepareToPlay()
            return p
        }
    }

    func play(_ e: Effect, volume: Float = 1) {
        guard effectsEnabled else { return }
        if players[e] == nil { players[e] = makePlayers(e) }
        guard let pool = players[e] else { return }
        let p = pool.first { !$0.isPlaying } ?? pool.first
        p?.currentTime = 0
        p?.volume = volume
        p?.play()
    }

    /// Removal sound by material: creak (wood/rope), scrape (stone), ring (steel/brass).
    func removed(_ material: Material) {
        switch material {
        case .wood, .rope: play(.creak, volume: 0.8)
        case .stone: play(.scrape, volume: 0.8)
        case .steel, .brass: play(.ring, volume: 0.7)
        }
        play(.tick, volume: 0.6)
    }

    private func updateMusic() {
        if musicEnabled {
            ensureSession()
            if music == nil, let url = Bundle.main.url(forResource: "ambient", withExtension: "m4a")
                ?? Bundle.main.url(forResource: "ambient", withExtension: "wav") {
                music = try? AVAudioPlayer(contentsOf: url)
                music?.numberOfLoops = -1
                music?.volume = 0
            }
            music?.play()
            music?.setVolume(ducked ? 0.04 : 0.35, fadeDuration: 1.0)
        } else {
            music?.setVolume(0, fadeDuration: 0.4)
            let m = music
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                if !self.musicEnabled { m?.stop() }
            }
        }
    }
}
