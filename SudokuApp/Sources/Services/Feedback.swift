import AVFoundation
import Foundation
import UIKit
import os

/// What a move feels and sounds like.
///
/// Two channels with different rules, behind one call. Haptics ignore the silent
/// switch, because the switch silences *sound* and a phone on a table in a quiet
/// room is exactly where taps should still be felt. Sound respects it, because a
/// puzzle app is not important enough to be the exception. Both are muteable in
/// Settings, and sound is off by default.
///
/// The generators are created once and `prepare()`d when a board appears. That
/// is not micro-optimisation: the Taptic Engine takes tens of milliseconds to
/// spin up from cold, and an unprepared first tap arrives late enough to feel
/// like a different tap.
@MainActor
final class Feedback {

    var isHapticsEnabled: Bool
    var isSoundEnabled: Bool

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notice = UINotificationFeedbackGenerator()

    private var players: [GameEvent: AVAudioPlayer] = [:]
    private var isSessionConfigured = false

    private static let logger = Logger(subsystem: "dev.andcake.sudoku", category: "feedback")

    init(hapticsEnabled: Bool = true, soundEnabled: Bool = false) {
        isHapticsEnabled = hapticsEnabled
        isSoundEnabled = soundEnabled
    }

    /// Called when a board appears, and cheap enough to call again.
    func prepare() {
        guard isHapticsEnabled else { return }
        light.prepare()
        medium.prepare()
        notice.prepare()
    }

    func play(_ event: GameEvent) {
        if isHapticsEnabled { vibrate(event) }
        if isSoundEnabled { sound(event) }
    }

    // MARK: - Haptics

    /// The mapping from §6.4 of the plan, unchanged: light on placement,
    /// warning on conflict, medium on unit completion, success on solve.
    private func vibrate(_ event: GameEvent) {
        switch event {
        case .placed:
            light.impactOccurred()
            // Re-armed straight away: fast filling is a run of placements, and
            // the second one should feel like the first.
            light.prepare()
        case .conflicted:
            notice.notificationOccurred(.warning)
        case .unitCompleted:
            medium.impactOccurred()
            medium.prepare()
        case .solved:
            notice.notificationOccurred(.success)
        }
    }

    // MARK: - Sound

    private func sound(_ event: GameEvent) {
        configureSessionIfNeeded()
        guard let player = player(for: event) else { return }
        // Rewound rather than restarted: placing digits quickly should retrigger
        // the sound, not queue up four copies of it.
        player.currentTime = 0
        player.play()
    }

    /// `.ambient` is the whole reason sound respects the silent switch, and the
    /// reason a game does not stop someone's music. `mixWithOthers` is implied
    /// by the category and stated anyway, because a future category change that
    /// silently starts interrupting podcasts is a bug nobody would look for
    /// here.
    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.logger.error("No audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loaded on first use and kept. Four files totalling ~140 KB, decoded once;
    /// loading them at launch would pay for sound nobody has turned on.
    private func player(for event: GameEvent) -> AVAudioPlayer? {
        if let player = players[event] { return player }
        guard let url = Bundle.main.url(forResource: event.soundName, withExtension: "caf") else {
            Self.logger.error("Missing sound asset \(event.soundName, privacy: .public).caf")
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.6
            player.prepareToPlay()
            players[event] = player
            return player
        } catch {
            Self.logger.error("Could not load \(event.soundName, privacy: .public): \(error.localizedDescription)")
            return nil
        }
    }
}

extension GameEvent {
    /// Matches the names `scripts/make-sounds.swift` writes.
    var soundName: String {
        switch self {
        case .placed: "place"
        case .conflicted: "conflict"
        case .unitCompleted: "unit"
        case .solved: "solve"
        }
    }
}
