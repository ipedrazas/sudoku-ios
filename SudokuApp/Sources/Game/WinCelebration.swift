import SudokuKit
import SwiftUI

/// The reward for finishing: a summary of the solve, over a confetti burst.
///
/// The web app fires `canvas-confetti` for three seconds
/// (`useGameBoard.ts:404-428`). There is no SwiftUI equivalent and the package
/// takes no dependencies, so the particles below are hand-rolled — which turns
/// out to be an advantage, because it lets the whole thing collapse to a still
/// frame under Reduce Motion rather than being all-or-nothing.
struct WinCelebration: View {
    @Bindable var session: GameSession
    var onNewGame: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                ConfettiView(seed: UInt64(session.elapsedSeconds + 1))
                    .allowsHitTesting(false)
            }

            summary
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Solved in \(session.formattedTime)")
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                // A single settling bounce reads as celebration without the
                // screen moving for three seconds.
                .symbolEffect(.bounce, options: reduceMotion ? .nonRepeating : .repeat(2))

            Text("Solved")
                .font(.title2.bold())

            HStack(spacing: 24) {
                statistic("Time", session.formattedTime)
                statistic("Difficulty", session.difficulty.name)
                if session.hintPoints > 0 {
                    statistic("Hints", String(session.hintPoints))
                }
            }

            if !session.unlockedAchievements.isEmpty {
                unlocked
            }

            HStack(spacing: 12) {
                Button("New game", action: onNewGame)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("win.newGame")
                Button("Review board") { session.dismissWinSummary() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("win.review")
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 20, y: 8)
        .padding(.horizontal, 24)
        .accessibilityIdentifier("win.summary")
    }

    /// Anything this solve unlocked.
    ///
    /// Shown here rather than as a separate interruption: the achievement is
    /// part of the reward for the puzzle you just finished, and a second card to
    /// dismiss would make it feel like admin. The full grid, with its own unlock
    /// animation, is P6-5.
    private var unlocked: some View {
        VStack(spacing: 8) {
            Divider()
            ForEach(session.unlockedAchievements) { achievement in
                HStack(spacing: 10) {
                    Image(systemName: Self.symbol(for: achievement.icon))
                        .foregroundStyle(.yellow)
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(achievement.name)
                            .font(.subheadline.weight(.semibold))
                        Text(achievement.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityIdentifier("win.achievements")
    }

    /// The engine names icon families rather than SF Symbols, because it has no
    /// business knowing what platform is drawing it.
    private static func symbol(for icon: String) -> String {
        switch icon {
        case "zap": "bolt.fill"
        case "trophy": "trophy.fill"
        case "fire": "flame.fill"
        default: "star.fill"
        }
    }

    private func statistic(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Confetti

/// A short particle burst.
///
/// Particles are generated from a `SeededRandom` rather than the global RNG —
/// SudokuKit bans the latter so dailies stay reproducible, and SwiftLint applies
/// that rule across the whole repo. Determinism costs nothing here and makes the
/// effect reproducible in a screenshot.
private struct ConfettiView: View {
    let seed: UInt64

    private static let duration: TimeInterval = 2.5
    private static let count = 90

    private struct Particle {
        let x: Double
        let hue: Double
        let size: Double
        let delay: Double
        let drift: Double
        let spin: Double
    }

    private var particles: [Particle] {
        var rng = SeededRandom(seed: seed)
        return (0..<Self.count).map { _ in
            Particle(
                x: Double(rng.nextBounded(1000)) / 1000,
                hue: Double(rng.nextBounded(1000)) / 1000,
                size: 5 + Double(rng.nextBounded(7)),
                delay: Double(rng.nextBounded(600)) / 1000,
                drift: Double(rng.nextBounded(200)) / 1000 - 0.1,
                spin: Double(rng.nextBounded(720)) - 360
            )
        }
    }

    var body: some View {
        let particles = particles

        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for particle in particles {
                    draw(particle, in: &context, size: size, now: now)
                }
            }
        }
    }

    private func draw(_ particle: Particle, in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        // A stable phase so every particle falls at its own offset without
        // needing per-frame state.
        let phase = (now + particle.delay).truncatingRemainder(dividingBy: Self.duration) / Self.duration
        guard phase > 0 else { return }

        let x = particle.x * size.width + particle.drift * size.width * phase
        let y = phase * phase * size.height * 1.2 - size.height * 0.1
        guard y < size.height else { return }

        let rectangle = CGRect(
            x: -particle.size / 2, y: -particle.size / 2,
            width: particle.size, height: particle.size * 0.6
        )

        context.drawLayer { layer in
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .degrees(particle.spin * phase))
            layer.opacity = 1 - phase
            layer.fill(
                Path(roundedRect: rectangle, cornerRadius: 1),
                with: .color(Color(hue: particle.hue, saturation: 0.75, brightness: 0.95))
            )
        }
    }
}
