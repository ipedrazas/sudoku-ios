import SudokuKit
import SwiftUI

/// The home screen: what you were playing, and what you could play next.
///
/// Deliberately thin. The real shell — daily, calendar, stats, settings, and a
/// `NavigationSplitView` sidebar on iPad — arrives with the phases that fill
/// those screens.
struct RootView: View {
    let provider: PuzzleProvider
    let library: GameLibrary
    let daily: DailyModel
    let stats: StatsModel
    let settings: AppSettings
    let snapshots: SnapshotPublisher
    /// Set by the app when a link is opened; consumed here and cleared.
    @Binding var link: DeepLink?

    /// Where the stack can go. The game is a destination like any other, so
    /// finishing a daily returns to the calendar it was started from rather than
    /// dumping the player back at the top.
    enum Route: Hashable {
        case daily
        case calendar
        case stats
        case importPuzzle
        case settings
        case game
    }

    @State private var path: [Route] = []
    @State private var session: GameSession?
    /// Achievements unlocked by the solve just finished, so the grid can mark
    /// them when the player goes looking. Cleared when a new game starts.
    @State private var recentlyUnlocked: Set<String> = []
    @State private var importModel = ImportModel()
    /// Owned here rather than by the game screen so its generators outlive one
    /// board — the whole point of preparing them is not paying for it again.
    @State private var feedback = Feedback()
    @State private var showsWelcome = false
    /// The source for the zoom into a game. A namespace rather than a boolean
    /// because the transition is matched: the row grows into the board.
    @Namespace private var transition

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationDestination(for: Route.self, destination: destination)
        }
        .task {
            provider.warmUp()
            library.refresh()
            daily.refresh()
            stats.refresh()
            if let difficulty = Self.launchDifficulty { start(difficulty) }
            applyFeedbackSettings()
            showWelcomeIfNeeded()
            await publishSnapshot()
        }
        .sheet(isPresented: $showsWelcome) {
            WelcomeSheet { showsWelcome = false }
        }
        // Covers the back button and the back swipe, which no callback of ours
        // would otherwise hear about — a session left attached would keep
        // autosaving from behind whatever replaced it.
        .onChange(of: path) { _, path in
            if !path.contains(.game) { releaseSession() }
        }
        // A setting changed while a game is open applies to that game, rather
        // than to the next one — which is what the player just asked for.
        .onChange(of: settings.highlightsMistakes) { _, value in session?.showsConflicts = value }
        .onChange(of: settings.inputMode) { _, value in session?.inputMode = value }
        .onChange(of: settings.inactivityMinutes) { _, value in session?.inactivityMinutes = value }
        // Muting takes effect on the move being made, not the next game.
        .onChange(of: settings.hapticsEnabled) { _, _ in applyFeedbackSettings() }
        .onChange(of: settings.soundEnabled) { _, _ in applyFeedbackSettings() }
        // A link may arrive before this view exists (a cold launch from a widget
        // tap) or while a game is open, so it is consumed on change *and* on
        // appear.
        .onChange(of: link) { _, link in follow(link) }
        .task { follow(link) }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .daily:
            DailyScreen(model: daily, onPlay: playDaily) { path.append(.calendar) }
        case .calendar:
            CalendarScreen(model: daily, onPlay: playDaily)
        case .stats:
            StatsScreen(model: stats, highlighting: recentlyUnlocked)
        case .importPuzzle:
            ImportScreen(model: importModel) { puzzle in
                play(library.start(puzzle, source: .imported))
            }
        case .settings:
            SettingsScreen(settings: settings, stats: stats, onEraseAll: eraseAll)
        case .game:
            if let session {
                GameScreen(session: session) { endGame() }
                    // The board grows out of the row that started it. A push
                    // would slide a full-screen grid in from the side; this says
                    // "that thing you tapped became this", which is what
                    // actually happened.
                    .navigationTransition(.zoom(sourceID: Route.game, in: transition))
            }
        }
    }

    // MARK: - Home

    /// A list rather than the centred stack this screen started as, because it
    /// now has two jobs: resuming and starting. Swipe-to-delete is the other
    /// reason — it is free in a `List` and hand-rolled anywhere else.
    private var home: some View {
        List {
            Section {
                Button {
                    path.append(.daily)
                } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily puzzle")
                                .font(.headline)
                            Text(dailySubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.daily")

                Button {
                    path.append(.stats)
                } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stats")
                                .font(.headline)
                            Text(statsSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.stats")

                navigationRow(
                    title: "Import a puzzle",
                    subtitle: "Type one in from a newspaper",
                    route: .importPuzzle,
                    identifier: "home.import"
                )

                navigationRow(
                    title: "Settings",
                    subtitle: "How the game plays and feels",
                    route: .settings,
                    identifier: "home.settings"
                )
            }

            // Nothing saved and nothing ever finished: a first launch, or one
            // after "delete all data". Said in one line rather than as a
            // `ContentUnavailableView`, which fills a third of the screen and
            // pushes the difficulty rows — the thing this screen is for — below
            // the fold on the one launch where nobody knows to scroll.
            if library.savedGames.isEmpty, stats.stats.totalFinished == 0 {
                Section("In progress") {
                    Text("Nothing yet. Games save themselves as you play, and turn up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !library.savedGames.isEmpty {
                Section("In progress") {
                    ForEach(Array(library.savedGames.enumerated()), id: \.element.id) { index, summary in
                        Button {
                            resume(summary)
                        } label: {
                            SavedGameRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("resume.\(index)")
                        .matchedTransitionSource(id: Route.game, in: transition)
                    }
                    .onDelete(perform: delete)
                }
            }

            Section {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Button {
                        start(difficulty)
                    } label: {
                        HStack {
                            Text(difficulty.name)
                                .font(.headline)
                            Spacer()
                            Text(hint(for: difficulty))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // Without this the row is only tappable where there is
                        // text, and the gap in the middle does nothing.
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("difficulty.\(difficulty.rawValue)")
                    // Every row that can open a board is a source for the same
                    // zoom. Only the one actually tapped is on screen when the
                    // transition runs, so they cannot compete.
                    .matchedTransitionSource(id: Route.game, in: transition)
                }
            } header: {
                Text("New game")
            } footer: {
                Text("Every puzzle is solvable by logic alone.")
            }
        }
        .navigationTitle("Sudoku and Cake")
    }

    private var dailySubtitle: String {
        let streak = daily.streak.current
        guard let today = daily.today() else {
            return streak > 0 ? "Not played — \(streak) day streak at stake" : "A new puzzle every day"
        }
        if today.isCompleted { return streak > 0 ? "Solved — \(streak) day streak" : "Solved" }
        return today.isInProgress ? "In progress" : "Not played yet"
    }

    private func navigationRow(
        title: String,
        subtitle: String,
        route: Route,
        identifier: String
    ) -> some View {
        Button {
            path.append(route)
        } label: {
            LabeledContent {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var statsSubtitle: String {
        let solved = stats.stats.totalFinished
        guard solved > 0 else { return "Nothing solved yet" }
        let unlocked = stats.unlockedCount
        let puzzles = solved == 1 ? "1 puzzle" : "\(solved) puzzles"
        return unlocked > 0 ? "\(puzzles) · \(unlocked) achievements" : puzzles
    }

    /// Names the technique each rung actually requires. The difficulty ladder is
    /// defined by technique rather than clue count, so saying so is more honest
    /// than "medium" and teaches the vocabulary the hints will use.
    private func hint(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .easy: "scanning"
        case .medium: "locked candidates"
        case .hard: "and a little more"
        case .expert: "hidden pairs, X-wings"
        }
    }

    // MARK: - Actions

    private func start(_ difficulty: Difficulty) {
        Task {
            let puzzle = await provider.newGame(difficulty)
            let session = library.start(puzzle)
            play(session)
            // After `play`, not before: prefilling an unconfigured session fills
            // it with mistake highlighting off and no feedback attached, so a
            // screenshot run reaches the win card without ever going through the
            // path a player goes through. Filling a session that is already on
            // screen is what actually happens when someone plays.
            Self.prefill(session)
        }
    }

    private func resume(_ summary: SavedGameSummary) {
        play(library.resume(summary), isNew: false)
    }

    /// Goes where a link asked, and clears it so a later redraw does not go
    /// there again.
    ///
    /// Every route starts by emptying the stack. A link is a jump, not a push:
    /// arriving from the Lock Screen to find three screens of someone else's
    /// history behind the back button is disorienting, and the daily is where
    /// every widget points anyway.
    private func follow(_ link: DeepLink?) {
        guard let link else { return }
        self.link = nil
        path.removeAll()

        switch link {
        case .daily:
            // A solved daily opens its screen rather than its board. Tapping
            // "done ✓" and landing in a finished grid with nothing to do is a
            // dead end; the daily screen at least offers the calendar.
            if daily.isCompleted() {
                path = [.daily]
            } else {
                path = [.daily]
                playDaily(Date())
            }
        case .calendar:
            // Pushed behind the calendar so Back goes somewhere sensible rather
            // than straight out to the home screen.
            path = [.daily, .calendar]
        case .stats:
            path = [.stats]
        case .puzzle(let code):
            openShared(code)
        }
    }

    /// Opens a puzzle carried whole in a share code.
    ///
    /// Decoding is strict — `PuzzleSharing` refuses a code that does not solve
    /// uniquely — and a refusal is silent: the link came from outside the app,
    /// and an alert about a malformed code is a worse first impression than
    /// simply arriving at the home screen.
    private func openShared(_ code: String) {
        guard let puzzle = PuzzleSharing.generatedPuzzle(from: code) else { return }
        play(library.start(puzzle, source: .shared))
    }

    /// Plays the daily for a date — today's from the daily screen, any past
    /// day's from the calendar.
    private func playDaily(_ date: Date) {
        Task { play(await library.daily(for: date), isNew: false) }
    }

    /// Starts a freshly created session: applies the settings, then shows it.
    private func play(_ session: GameSession, isNew: Bool = true) {
        configure(session)
        // Notes are filled at the start of a *new* game only. Doing it on resume
        // would overwrite marks the player made by hand.
        if isNew, settings.autoFillNotes { session.autoFillNotes() }
        show(session)
    }

    /// Everything a session takes from settings rather than deciding itself.
    private func configure(_ session: GameSession) {
        session.showsConflicts = settings.highlightsMistakes
        session.inputMode = settings.inputMode
        session.inactivityMinutes = settings.inactivityMinutes
        // Wired here rather than in the game screen so every session gets it,
        // including one opened straight from a link with no screen in between.
        session.didEmit = { [feedback] event in feedback.play(event) }
        // The Taptic Engine takes tens of milliseconds to wake, which is long
        // enough for the first tap of a game to feel like it missed.
        feedback.prepare()
    }

    /// Shows the welcome sheet on a first launch, and never again.
    ///
    /// Not shown when something already has somewhere to be: a launch argument,
    /// or a link that was tapped. A screenshot run, a UI test and a shared
    /// puzzle all arrive with an intention, and a sheet in front of it is an
    /// obstacle rather than a welcome.
    ///
    /// `-skipWelcome` and `-forceWelcome` exist because "have you seen this
    /// before" is per-simulator state that no launch argument otherwise clears:
    /// `-inMemoryStore` empties the store but not `UserDefaults`, so without
    /// these a UI test would pass or fail depending on whether that simulator
    /// had ever run the app before.
    private func showWelcomeIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-forceWelcome") {
            showsWelcome = true
            return
        }
        guard !arguments.contains("-skipWelcome") else { return }
        guard !settings.hasSeenWelcome, link == nil, Self.launchDifficulty == nil else { return }
        settings.hasSeenWelcome = true
        showsWelcome = true
    }

    private func applyFeedbackSettings() {
        feedback.isHapticsEnabled = settings.hapticsEnabled
        feedback.isSoundEnabled = settings.soundEnabled
        feedback.prepare()
    }

    private func show(_ session: GameSession) {
        // Last game's unlocks stop being news the moment a new one starts.
        recentlyUnlocked = []
        self.session = session
        if path.last != .game { path.append(.game) }
    }

    /// Wipes the store and returns to a clean home screen.
    private func eraseAll() {
        releaseSession()
        path.removeAll()
        library.eraseEverything()
        daily.refresh()
        stats.refresh()
        // Including the widgets, which would otherwise keep showing a streak
        // from a history that no longer exists.
        snapshots.publish()
    }

    /// Makes sure today's daily exists, then tells the widgets what is true.
    ///
    /// Generating here rather than waiting for the player to open the daily is
    /// what lets the mini-board widget show today's actual grid. It costs one
    /// carve a day, off the main actor.
    private func publishSnapshot() async {
        await library.ensureDaily(for: Date())
        snapshots.publish()
    }

    private func delete(at offsets: IndexSet) {
        for summary in offsets.map({ library.savedGames[$0] }) {
            // Deleting the game currently on screen would leave a session with
            // nowhere to save; the library detaches it, and the board is only
            // ever behind this screen, never in front of it.
            if summary.id == session?.id { session = nil }
            library.delete(summary)
        }
    }

    /// Leaves the game, saving it on the way out, and returns to whatever
    /// pushed it.
    private func endGame() {
        if path.last == .game { path.removeLast() }
        releaseSession()
    }

    /// Idempotent, because it is called both explicitly and from the path
    /// observer that catches the back button.
    private func releaseSession() {
        guard let session else { return }
        // Carried out of the session before it goes, so the achievements grid
        // can mark what this solve earned whenever the player looks.
        recentlyUnlocked = Set(session.unlockedAchievements.map(\.key))

        library.detach()
        self.session = nil
        // The game just ended, and every screen behind it says something about
        // games that have ended.
        daily.refresh()
        stats.refresh()
        // The widgets are one of those screens, and the one the player is most
        // likely to see next — finishing a daily and going straight to the Home
        // Screen is the common path, not the unusual one.
        snapshots.publish()
    }

    // MARK: - Launch arguments

    /// Lets a launch argument open straight into a game: `-startGame easy`.
    ///
    /// A development affordance, and a deliberate one. Screenshot and UI-test
    /// runs otherwise have to drive the picker first, which is slow and makes
    /// them fail for reasons that have nothing to do with what they are testing.
    private static var launchDifficulty: Difficulty? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-startGame"), index + 1 < arguments.count else {
            return nil
        }
        return Difficulty(rawValue: arguments[index + 1])
    }

    /// `-prefill N` fills all but N cells from the solution.
    ///
    /// The companion to `-startGame`, and for the same reason: the states worth
    /// looking at hardest — a nearly finished grid, the win card — are the most
    /// tedious to reach by tapping. Screenshots and UI tests use it; nothing
    /// else does.
    private static func prefill(_ session: GameSession) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-prefill"), index + 1 < arguments.count,
            let remaining = Int(arguments[index + 1])
        else { return }

        let empties = session.board.emptyCells
        for cell in empties.dropLast(max(0, remaining)) {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
        session.selection = nil
    }
}

// MARK: - Saved game row

/// One game in progress: what it is, how far in, and how long ago.
///
/// The progress bar counts the cells the *player* has to fill, not all 81 — a
/// fresh easy puzzle arrives 34/81 filled and showing that as 42% done would be
/// flattering nonsense.
private struct SavedGameRow: View {
    let summary: SavedGameSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.difficulty.name)
                    .font(.headline)
                Spacer()
                Text(summary.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: summary.progress)

            HStack {
                Label(summary.formattedTime, systemImage: "clock")
                Spacer()
                Text("^[\(summary.remainingCells) cell](inflect: true) left")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(summary.difficulty.name), \(summary.formattedTime) played, \(summary.remainingCells) cells left"
        )
    }
}
