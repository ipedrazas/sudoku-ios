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
    /// Set by the app when a link is opened; consumed here and cleared.
    @Binding var sharedPuzzle: GeneratedPuzzle?

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
        // A link may arrive before this view exists (a cold launch from a tap)
        // or while a game is open, so it is consumed on change *and* on appear.
        .onChange(of: sharedPuzzle) { _, puzzle in openShared(puzzle) }
        .task { openShared(sharedPuzzle) }
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
            Self.prefill(session)
            play(session)
        }
    }

    private func resume(_ summary: SavedGameSummary) {
        play(library.resume(summary), isNew: false)
    }

    /// Opens a puzzle that arrived from a link, and clears it so a later
    /// redraw does not open it again.
    private func openShared(_ puzzle: GeneratedPuzzle?) {
        guard let puzzle else { return }
        sharedPuzzle = nil
        path.removeAll()
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
