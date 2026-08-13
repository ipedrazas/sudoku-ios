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
    @State private var showsHint = false
    @State private var hintLevel: HintLevel = .nudge
    @State private var sharedImage: Image?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// One second, driving `session.tick`. The session keeps its own elapsed
    /// time rather than reading the clock, which is what makes it testable
    /// without waiting on real seconds.
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            Group {
                if wantsSideBySide(in: proxy.size) {
                    regularLayout
                } else {
                    compactLayout(in: proxy.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // Presented by a flag rather than by `sheet(item:)`. Swapping to a
        // different hint replaces the value, and an item-bound sheet reads a new
        // identity as a new sheet: the old one animates out and the new one in,
        // which is a lot of movement for "same question, different answer".
        .sheet(isPresented: $showsHint) {
            if let hint {
                HintSheet(
                    hint: hint,
                    level: $hintLevel,
                    session: session,
                    onDifferent: showDifferentHint,
                    onDismiss: dismissHint
                )
            }
        }
        // Swiping the sheet away is *Done*, not a third state. Without this the
        // flag drops but the hint does not, and the board stays lit for a sheet
        // that is no longer on screen.
        .onChange(of: showsHint) { _, isShowing in
            if !isShowing { dismissHint() }
        }
        .sheet(isPresented: Binding(get: { sharedImage != nil }, set: { if !$0 { sharedImage = nil } })) {
            if let sharedImage {
                ShareImageSheet(image: sharedImage, difficulty: session.difficulty)
            }
        }
        .overlay {
            if session.showsWinSummary {
                WinCelebration(session: session, onNewGame: onNewGame)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: session.showsWinSummary)
        // The offer, not an interruption: the clock is still running behind it,
        // and declining costs nothing.
        .alert("Still there?", isPresented: idlePrompt) {
            Button("Pause") { session.acceptIdlePause() }
            Button("Keep going", role: .cancel) { session.declineIdlePause() }
        } message: {
            Text("The clock is still running. Pause it so a break doesn't count against your time?")
        }
    }

    // MARK: - Layouts

    /// Whether to put the controls beside the board rather than under it.
    ///
    /// Size class alone was the wrong question, and an iPad in portrait was the
    /// wrong answer to it. A 13-inch portrait screen is regular-width, so it got
    /// the side-by-side layout: the board capped at 640 points against a column
    /// of controls, and the remaining half of a very tall screen left empty
    /// above and below. Players asked for the numbers under the grid, which is
    /// the same request as "use the height" — stacked, the board grows by around
    /// half again on that screen.
    ///
    /// Landscape genuinely does want the split: stacking there would give the
    /// board only what is left of the height after a control bar and a pad,
    /// which is smaller than what it gets beside them.
    private func wantsSideBySide(in size: CGSize) -> Bool {
        guard sizeClass == .regular else { return false }
        // Not `>` — a 1:1 split view is as good as landscape for this, and the
        // margin keeps a near-square window from flipping layout as it is
        // dragged through the boundary.
        return size.width > size.height * 1.1
    }

    /// iPhone, and any tall screen: board on top, controls under it (§8.1).
    ///
    /// Centring the board instead only moved the dead band above it rather than
    /// removing it, and cost the eye its anchor.
    ///
    /// The board is capped at whatever the pad below it needs, which is what
    /// stops a 13-inch iPad from drawing a board so large the digits have to be
    /// looked *up* at. The cap is generous — the point of the change was more
    /// board, not a phone layout centred in a lot of grey.
    private func compactLayout(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            header
            BoardView(session: session)
                .frame(maxWidth: boardWidth(in: size))

            // On a phone the gap is unbounded on purpose: the controls belong in
            // the bottom third, where a thumb reaches. On a tablet nothing
            // reaches the bottom of a 1366-point screen, and an unbounded gap
            // there would strand the pad a screen away from the board it acts on
            // — which is the failure the side-by-side layout was built to avoid,
            // reintroduced by stacking. Bounded, the whole stack centres instead.
            Spacer(minLength: 0)
                .frame(maxHeight: sizeClass == .regular ? 56 : .infinity)

            ControlBar(session: session, onHint: requestHint)
            NumberPad(session: session, layout: .row)
        }
        .frame(maxHeight: .infinity, alignment: sizeClass == .regular ? .center : .top)
        // Controls on a tablet do not want to be as wide as the tablet: a number
        // pad stretched across a 1024-point screen puts 1 and 9 a hand's width
        // apart.
        .frame(maxWidth: sizeClass == .regular ? Self.tabletContentWidth : .infinity)
        .frame(maxWidth: .infinity)
    }

    /// How wide the board and the controls under it are allowed to get.
    ///
    /// 780 rather than the 640 the side-by-side layout capped the board at, and
    /// rather than the full width. It is set from the *number pad*: nine keys
    /// across this give about 82 points each, which is a comfortable target,
    /// where the full 1000 points of an iPad's width gives 105 and a row that
    /// has to be traversed rather than aimed at.
    private static let tabletContentWidth: CGFloat = 780

    /// The board's ceiling in the stacked layout: whichever of the width and the
    /// leftover height binds first, so the grid grows into the space an iPad has
    /// and never past what the controls need.
    private func boardWidth(in size: CGSize) -> CGFloat {
        guard sizeClass == .regular else { return .infinity }
        // Header, control bar, number pad and the spacings between them, at the
        // default text size. Only binds on a short regular-width window; a full
        // iPad portrait screen has height to spare.
        let controlsHeight: CGFloat = 260
        return min(Self.tabletContentWidth, max(320, size.height - controlsHeight))
    }

    /// iPad in landscape, and iPhone Max in landscape (§8.2).
    ///
    /// Stacking in landscape gives a board the size of a dinner plate with the
    /// controls marooned at the bottom edge — a reach of most of the screen
    /// between looking and tapping. Side by side keeps the board at a readable
    /// size and the controls next to it.
    private var regularLayout: some View {
        HStack(alignment: .center, spacing: 32) {
            BoardView(session: session)
                .frame(maxWidth: 640)

            // Sized to its content and centred against the board. Letting this
            // column fill the height instead stranded the pad at the bottom
            // edge, a screen away from the board it acts on.
            VStack(spacing: 24) {
                header
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
                // Digits roll rather than snap. A clock that jumps every second
                // in the corner of a puzzle is a thing the eye keeps going back
                // to; one that rolls is a thing it stops noticing.
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .default, value: session.elapsedSeconds)
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
                // Play settings moved to the Settings screen in P7-6. What is
                // left here is what belongs to *this* puzzle rather than to the
                // app: restarting it, marking it up, and passing it on.
                if let link = PuzzleSharing.url(for: session.puzzle.puzzle) {
                    ShareLink(
                        item: link,
                        subject: Text("A \(session.difficulty.name) Sudoku"),
                        message: Text("Same puzzle, no account needed.")
                    ) {
                        Label("Share this puzzle", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("control.share")
                }
                Button("Share as image", systemImage: "photo") { sharedImage = boardImage() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("control.menu")
            .accessibilityLabel("More")
        }
    }

    /// Bound rather than stored: the session decides when the offer is due, so
    /// there is no second copy of that state to drift.
    private var idlePrompt: Binding<Bool> {
        Binding(
            get: { session.isIdlePromptDue },
            set: { if !$0 { session.declineIdlePause() } }
        )
    }

    // MARK: - Hints

    private func requestHint() {
        hintLevel = .nudge
        let hint = session.hint(at: .nudge)
        // The board lights up from the first level, not the third. A nudge that
        // names a technique without saying where is a riddle; a nudge that names
        // it and points is a hint.
        session.show(hint)
        self.hint = hint
        showsHint = true
    }

    /// A different hint, at the level the player is already reading at.
    ///
    /// Not a reset to `.nudge`: someone who has read down to "explain" and still
    /// does not follow it is asking for another explanation, not to start the
    /// escalation over.
    private func showDifferentHint() {
        guard let current = hint else { return }
        let next = session.differentHint(from: current)
        session.show(next)
        hint = next
    }

    private func boardImage() -> Image? {
        BoardImage.render(session.puzzle.puzzle, difficulty: session.difficulty)
    }

    private func dismissHint() {
        showsHint = false
        hint = nil
        session.dismissHint()
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
///
/// **Every state of this sheet has a way forward.** It used not to. The
/// escalation ran nudge → locate → explain → reveal, and at reveal the sheet
/// offered a button only when `hint.placement` was set — which every elimination
/// technique leaves nil, because "rule 4 out of these two cells" fills nothing
/// in. A player who did not follow an X-wing arrived at the last level of the
/// last hint and found one control: *Done*. Three of them wrote in to say so.
///
/// Two controls answer that, and both are present at every level rather than
/// only at the end:
///
/// - **Show me a different hint** — the engine has more than one deduction
///   available and used to only ever offer the first. Asking again is free.
/// - **Fill in a cell for me** — costs what a reveal costs, and always works,
///   because `Hint.answer` is populated for every outcome on an unsolved board.
private struct HintSheet: View {
    let hint: Hint
    @Binding var level: HintLevel
    @Bindable var session: GameSession
    var onDifferent: () -> Void
    var onDismiss: () -> Void

    private static let detent = PresentationDetent.height(320)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Scrolls so that large Dynamic Type lengthens the text rather
                // than pushing the controls off the bottom of the detent — the
                // P9-3 failure, in a sheet that cannot afford it: the controls
                // being unreachable is the whole defect this sheet exists to fix.
                ScrollView {
                    Text(hint.text(at: level))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("hint.text")
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: 8) {
                    primaryButton

                    HStack(spacing: 8) {
                        if session.hasDifferentHint(from: hint) {
                            Button(action: onDifferent) {
                                Label("Show me a different hint", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity)
                                    .lineLimit(2)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("hint.different")
                        }

                        if showsAnswerEscape {
                            Button {
                                session.revealAnswer(hint, from: level)
                                onDismiss()
                            } label: {
                                Label("Fill in a cell for me", systemImage: "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                                    .lineLimit(2)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("hint.answer")
                        }
                    }
                    .font(.subheadline)
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
        // Short enough that the board — and the cells the hint just lit up —
        // stay on screen behind it. A hint that hides what it is pointing at is
        // a worse hint. `.large` is offered as well so a long explanation at an
        // accessibility text size can be read without scrolling a small box.
        .presentationDetents([Self.detent, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: Self.detent))
    }

    @ViewBuilder
    private var primaryButton: some View {
        if level != .reveal {
            Button(action: escalate) {
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
                Label(applyLabel, systemImage: applySymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("hint.apply")
        }
    }

    /// Offered whenever the primary button is not already the answer: at reveal
    /// with a placement, "Fill it in" *is* this control, and two buttons that do
    /// the same thing read as two different things.
    private var showsAnswerEscape: Bool {
        guard hint.answer != nil else { return false }
        return !(level == .reveal && hint.placement != nil)
    }

    private var nextLabel: LocalizedStringKey {
        switch level {
        case .nudge: "Where?"
        case .locate: "Why?"
        case .explain: "Just tell me"
        case .reveal: ""
        }
    }

    /// A mistake hint carries a placement of 0 — "this should not say what it
    /// says" — so the button offers to erase rather than to fill in.
    private var isMistake: Bool {
        if case .mistake = hint.outcome { return true }
        return false
    }

    private var applyLabel: LocalizedStringKey { isMistake ? "Erase it" : "Fill it in" }
    private var applySymbol: String { isMistake ? "eraser" : "wand.and.stars" }

    private func escalate() {
        let previous = level
        guard let next = HintLevel(rawValue: level.rawValue + 1) else { return }
        level = next
        session.hint(at: next, previousLevel: previous)
    }
}

// MARK: - Share as image

/// A rendered board, ready to send.
///
/// Shown before sharing rather than handed straight to the share sheet: an image
/// you have not seen is one you might not want to send.
private struct ShareImageSheet: View {
    let image: Image
    let difficulty: Difficulty

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360)
                    .shadow(radius: 8, y: 4)

                ShareLink(
                    item: image,
                    preview: SharePreview("A \(difficulty.name) Sudoku", image: image)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("share.image")
            }
            .padding()
            .navigationTitle("Share as image")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
