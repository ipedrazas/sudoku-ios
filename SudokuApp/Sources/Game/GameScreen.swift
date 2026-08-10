import SudokuKit
import SwiftUI

/// One puzzle: board above, controls below.
///
/// The compact-width arrangement from §8.1 — board near the top, controls in the
/// bottom third where a thumb reaches. The regular-width split for iPad is
/// P3-10.
struct GameScreen: View {
    @Bindable var session: GameSession
    var onNewGame: () -> Void

    @State private var hint: Hint?
    @State private var hintLevel: HintLevel = .nudge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// One second, driving `session.tick`. The session keeps its own elapsed
    /// time rather than reading the clock, which is what makes it testable
    /// without waiting on real seconds.
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .keyboardCommands(session: session, onHint: requestHint)
        .onReceive(clock) { _ in session.tick() }
        .animation(reduceMotion ? nil : .snappy, value: session.isSolved)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: session.celebratingUnits)
        .task(id: session.celebratingUnits) { await clearCelebrationAfterDelay() }
        .navigationTitle(session.difficulty.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $hint) { hint in
            HintSheet(hint: hint, level: $hintLevel, session: session) { self.hint = nil }
        }
    }

    // MARK: - Layouts

    /// iPhone portrait, and iPad in Slide Over or a narrow split.
    ///
    /// Board at the top, controls at the bottom (§8.1). Centring the board
    /// instead only moved the dead band above it rather than removing it, and
    /// cost the eye its anchor.
    private var compactLayout: some View {
        VStack(spacing: 12) {
            header
            BoardView(session: session)
            Spacer(minLength: 0)
            if session.isSolved { solvedBanner }
            ControlBar(session: session, onHint: requestHint)
            NumberPad(session: session, layout: .row)
        }
    }

    /// iPad, and iPhone Max in landscape (§8.2).
    ///
    /// Stretching the compact layout to an iPad gives a board the size of a
    /// dinner plate with the controls marooned at the bottom edge — a reach of
    /// most of the screen between looking and tapping. Side by side keeps the
    /// board at a readable size and the controls next to it.
    private var regularLayout: some View {
        HStack(alignment: .center, spacing: 32) {
            BoardView(session: session)
                .frame(maxWidth: 640)

            // Sized to its content and centred against the board. Letting this
            // column fill the height instead stranded the pad at the bottom
            // edge, a screen away from the board it acts on.
            VStack(spacing: 24) {
                header
                if session.isSolved { solvedBanner }
                ControlBar(session: session, onHint: requestHint)
                NumberPad(session: session, layout: .grid)
            }
            .frame(maxWidth: 340)
        }
        // Centred vertically: side by side leaves real vertical slack on an
        // iPad in portrait, and pinning to the top pushed all of it below the
        // content where it read as the screen being unfinished.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Pieces

    /// Timer and pause. Pausing is manual here; the inactivity prompt that
    /// offers it automatically is P3-9.
    private var header: some View {
        HStack {
            Label(session.formattedTime, systemImage: "clock")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Elapsed time \(session.formattedTime)")

            Spacer()

            Button {
                session.togglePause()
            } label: {
                Image(systemName: session.isPaused ? "play.circle" : "pause.circle")
                    .font(.title3)
            }
            .disabled(session.isSolved)
            .accessibilityIdentifier("control.pause")
            .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
        }
    }

    private var solvedBanner: some View {
        Label("Solved in \(session.formattedTime)", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .transition(.scale.combined(with: .opacity))
            .accessibilityIdentifier("banner.solved")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("New game", systemImage: "plus", action: onNewGame)
                .accessibilityIdentifier("control.new")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Restart", systemImage: "arrow.counterclockwise") { session.restart() }
                Button("Fill in all notes", systemImage: "square.grid.3x3.topleft.filled") {
                    session.autoFillNotes()
                }
                Divider()
                // Settings has no screen of its own until P7-6; until then these
                // live where they are used rather than being unreachable.
                Toggle("Highlight mistakes", isOn: $session.showsConflicts)
                Picker("Input", selection: $session.inputMode) {
                    ForEach(InputMode.allCases, id: \.self) { Text($0.name).tag($0) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("control.menu")
            .accessibilityLabel("More")
        }
    }

    // MARK: - Hints

    private func requestHint() {
        hintLevel = .nudge
        hint = session.hint(at: .nudge)
    }

    /// The celebration is a fixed 2 s in the web app; here the view owns the
    /// timing and tells the session when it is done, so the session stays free
    /// of animation concerns.
    private func clearCelebrationAfterDelay() async {
        guard !session.celebratingUnits.isEmpty else { return }
        try? await Task.sleep(for: .seconds(2))
        session.clearCelebration()
    }
}

// MARK: - Hint sheet

/// Escalating hints: name the technique, point at it, explain it, then — only if
/// asked — give the answer.
private struct HintSheet: View {
    let hint: Hint
    @Binding var level: HintLevel
    @Bindable var session: GameSession
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(hint.text(at: level))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("hint.text")

                Spacer()

                if level != .reveal {
                    Button {
                        escalate()
                    } label: {
                        Label(nextLabel, systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("hint.more")
                } else if hint.placement != nil {
                    Button {
                        session.applyHint(hint)
                        onDismiss()
                    } label: {
                        Label("Fill it in", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("hint.apply")
                }
            }
            .padding()
            .navigationTitle("Hint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.height(240)])
    }

    private var nextLabel: String {
        switch level {
        case .nudge: "Where?"
        case .locate: "Why?"
        case .explain: "Just tell me"
        case .reveal: ""
        }
    }

    private func escalate() {
        let previous = level
        guard let next = HintLevel(rawValue: level.rawValue + 1) else { return }
        level = next
        session.hint(at: next, previousLevel: previous)
    }
}

extension Hint: @retroactive Identifiable {
    public var id: String { "\(outcome)" }
}
