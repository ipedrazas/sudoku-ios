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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            // Still, not absent. Reduce Motion asks for less movement, not for
            // less celebration, and someone who turns it on has still just
            // solved the puzzle. The particles are drawn at the moment the burst
            // is widest and simply do not move.
            ConfettiView(seed: UInt64(session.elapsedSeconds + 1), isAnimated: !reduceMotion)
                .allowsHitTesting(false)

            summary
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Solved in \(session.formattedTime)")
    }

    /// The card. At normal sizes it hugs its content; at accessibility sizes the
    /// summary scrolls **and the buttons do not**.
    ///
    /// The same content is roughly three times as tall at the largest sizes, and
    /// the first attempt at this — wrapping the whole card in a `ScrollView` —
    /// fixed the overflow by pushing "New game" below the fold. A celebration
    /// whose only way out has to be discovered by scrolling is a worse bug than
    /// the one it replaced, so the buttons are pinned outside the scrolling part
    /// and are on screen at every size.
    @ViewBuilder
    private var summary: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 16) {
                ScrollView {
                    summaryContent
                        .frame(maxWidth: .infinity)
                }
                // No rubber-banding when it already fits.
                .scrollBounceBehavior(.basedOnSize)

                actions
            }
            .frame(maxHeight: 560)
            .modifier(CardStyle())
        } else {
            VStack(spacing: 16) {
                summaryContent
                actions
            }
            .modifier(CardStyle())
        }
    }

    private var summaryContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                // A settling bounce reads as celebration without the screen
                // moving for three seconds — and none at all under Reduce
                // Motion. `options:` was the wrong lever: it chooses *how many*
                // times to bounce, so the setting was quietly turning two
                // bounces into one rather than into none. `isActive` is the one
                // that means "do not".
                .symbolEffect(.bounce, options: .repeat(2), isActive: !reduceMotion)

            Text("Solved")
                .font(.title2.bold())

            // Three statistics side by side stop fitting long before the
            // largest sizes, and a wrapped "Difficulty" over a stacked "Hints"
            // is worse than a short column of them.
            statisticsLayout {
                statistic("Time", session.formattedTime)
                statistic("Difficulty", session.difficulty.name)
                if session.hintPoints > 0 {
                    statistic("Hints", String(session.hintPoints))
                }
            }

            if !session.unlockedAchievements.isEmpty {
                unlocked
            }
        }
    }

    /// Two buttons in a row become "Ne w…" and "Re- view…" at accessibility
    /// sizes: a bordered button will not shrink its label, and there is no width
    /// to give it. Stacked, each gets the full card and reads as itself.
    private var actions: some View {
        buttonLayout {
            Button("New game", action: onNewGame)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("win.newGame")
            Button("Review board") { session.dismissWinSummary() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("win.review")
        }
    }

    /// The card's surface, corner and shadow, shared by both branches above so
    /// the card cannot come out looking like two different cards.
    ///
    /// **Opaque, not `.regularMaterial`.** The material looked better and cost
    /// the secondary text: "Time", "Difficulty" and every achievement detail
    /// took up their space and drew nothing at all. Secondary foreground styles
    /// are resolved against the backdrop they sit on, and over a blurred
    /// material inside a `ScrollView` they resolved to no contrast whatever —
    /// invisible in light mode *and* dark, which is how it survived the first
    /// two attempts to fix it as a layout problem and then as a colour one.
    ///
    /// An opaque surface makes every semantic colour behave the way it reads in
    /// the source. The blur was decoration; the labels are the content.
    private struct CardStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(24)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 20, y: 8)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .accessibilityIdentifier("win.summary")
        }
    }

    /// Row normally, column once the text is large enough that a row lies.
    private var statisticsLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 24))
    }

    private var buttonLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
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
                HStack(alignment: .top, spacing: 10) {
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
                    // Wrap rather than truncate. "Easy St…" over "Complete…"
                    // tells the player they earned something without telling
                    // them what, which is the one thing this section is for.
                    .fixedSize(horizontal: false, vertical: true)
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

    /// A number over what it means.
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
    /// False under Reduce Motion: the same burst, held still.
    var isAnimated = true

    private static let duration: TimeInterval = 2.5
    private static let count = 90

    /// Where in its fall each particle is frozen when nothing is moving. Far
    /// enough in that the burst has spread and the particles have turned, not so
    /// far that half of them have already fallen off the bottom.
    private static let stillPhase = 0.35

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

        if isAnimated {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    for particle in particles {
                        // A stable phase so every particle falls at its own
                        // offset without needing per-frame state.
                        let phase =
                            (now + particle.delay)
                            .truncatingRemainder(dividingBy: Self.duration) / Self.duration
                        draw(particle, in: &context, size: size, phase: phase)
                    }
                }
            }
        } else {
            Canvas { context, size in
                for particle in particles {
                    // The particle's own delay still spreads them out, so the
                    // still frame keeps the scatter of the moving one rather
                    // than lining every piece up on one row.
                    draw(particle, in: &context, size: size, phase: Self.stillPhase + particle.delay / 4)
                }
            }
        }
    }

    private func draw(_ particle: Particle, in context: inout GraphicsContext, size: CGSize, phase: Double) {
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
