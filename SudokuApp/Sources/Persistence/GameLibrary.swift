import Foundation
import SudokuKit

/// Owns the relationship between the game being played and the store.
///
/// `GameSession` knows nothing about persistence and `GameRepository` knows
/// nothing about play; this is the seam. It creates sessions, saves them as they
/// change, resumes them, and — when one is solved — writes the completion and
/// works out what it unlocked.
///
/// One session is tracked at a time. On iPad, multiple windows each get their
/// own library over the same repository, which works because every write is
/// keyed by puzzle id and the store is the only shared state.
@Observable
@MainActor
final class GameLibrary {

    /// Games in progress, most recently played first.
    private(set) var savedGames: [SavedGameSummary] = []

    /// The last thing that went wrong, if anything.
    ///
    /// Persistence failures do not interrupt play — losing a save is bad, losing
    /// the game in front of the player is worse — so they are recorded rather
    /// than thrown. Tests assert this stays nil.
    private(set) var lastError: (any Error)?

    private let repository: any GameRepository
    /// How long after a mutation the save fires. Injectable so tests do not wait
    /// a real second to prove a debounce.
    private let autosaveDelay: Duration

    private var session: GameSession?
    private var storedPuzzle: StoredPuzzle?
    private var autosaveTask: Task<Void, Never>?
    /// Guards against writing the same completion twice — `didChange` fires on
    /// every mutation and the board stays solved once it is.
    private var hasRecordedCompletion = false

    init(repository: any GameRepository, autosaveDelay: Duration = .seconds(1)) {
        self.repository = repository
        self.autosaveDelay = autosaveDelay
        refresh()
    }

    // MARK: - Starting and resuming

    /// A session for a freshly generated puzzle.
    ///
    /// Nothing is written yet. A puzzle the player looks at and abandons should
    /// leave no trace, and writing the record on the first save rather than here
    /// is what keeps the store free of orphans without a sweep to clean them up.
    func start(
        _ generated: GeneratedPuzzle,
        source: PuzzleSource = .generated,
        dateKey: String? = nil,
        showsConflicts: Bool = true
    ) -> GameSession {
        let stored = StoredPuzzle(generated: generated, source: source, dateKey: dateKey)
        let session = GameSession(id: stored.id, puzzle: generated, showsConflicts: showsConflicts)
        track(session, puzzle: stored)
        return session
    }

    /// The daily for a date: generated if this is the first time, resumed if it
    /// has been started, replayable if it has been finished.
    ///
    /// Unlike a generated game, the puzzle record is written **immediately**.
    /// That looks like a contradiction of the "nothing is written until the
    /// player does something" rule and is the opposite: for a daily the record
    /// *is* a cache keyed by date, and the point of the cache is that opening
    /// the 3rd of March twice costs one generation. It cannot orphan either —
    /// a date key is a reason to keep a puzzle.
    ///
    /// Generation is deterministic, so a store that has never seen this date
    /// produces the same grid as one that has.
    func daily(for date: Date, showsConflicts: Bool = true) async -> GameSession {
        let puzzle = await ensureDaily(for: date)

        let session = GameSession(
            id: puzzle.id,
            puzzle: puzzle.generated,
            restoring: try? repository.savedGame(puzzleID: puzzle.id),
            showsConflicts: showsConflicts
        )
        track(session, puzzle: puzzle)
        return session
    }

    /// The stored daily for a date, generating and caching it if this is the
    /// first time anyone has asked.
    ///
    /// The **only** writer of a dated puzzle row. `StoredPuzzle` mints a fresh
    /// `id`, so a second place that generated-and-saved a daily would leave two
    /// rows for one date key, `puzzle(dateKey:)` would answer with either, and a
    /// game saved against one of them would be orphaned by the other. That is
    /// why the widget snapshot publisher reads this state and never creates it.
    ///
    /// Called at launch as well as on open, so today's puzzle exists before the
    /// player asks for it: the widget can then show the real grid, and tapping
    /// "Daily" is instant rather than a carve.
    @discardableResult
    func ensureDaily(for date: Date) async -> StoredPuzzle {
        let dateKey = DailyPuzzle.dateKey(for: date)
        if let cached = try? repository.puzzle(dateKey: dateKey) { return cached }

        // Carving is solid CPU work — a medium puzzle is single-digit
        // milliseconds on this machine but several times that on the oldest
        // device worth supporting, and none of it belongs on the main actor.
        let generated = await Task.detached(priority: .userInitiated) {
            DailyPuzzle.generate(for: date)
        }.value

        // Between the check and here the main actor was given up, so another
        // caller may have generated the same day meanwhile. Generation is
        // deterministic, so the grids are identical — but the ids are not, and
        // keeping the one already in the store is what stops the duplicate.
        if let raced = try? repository.puzzle(dateKey: dateKey) { return raced }

        let puzzle = StoredPuzzle(generated: generated, source: .daily, dateKey: dateKey)
        do {
            try repository.save(puzzle: puzzle)
        } catch {
            lastError = error
        }
        return puzzle
    }

    /// A session picked up exactly where it was left.
    func resume(_ summary: SavedGameSummary, showsConflicts: Bool = true) -> GameSession {
        let session = GameSession(
            id: summary.puzzle.id,
            puzzle: summary.puzzle.generated,
            restoring: summary.state,
            showsConflicts: showsConflicts
        )
        track(session, puzzle: summary.puzzle)
        return session
    }

    /// Stops tracking the current session, saving it first.
    ///
    /// Called when the player leaves a game. Without it a session would keep
    /// autosaving from behind whatever replaced it.
    func detach() {
        flush()
        session?.didChange = nil
        session = nil
        storedPuzzle = nil
    }

    // MARK: - Saving

    /// Saves now rather than in a second's time.
    ///
    /// The other half of the debounce: the scene going inactive is the last
    /// moment anything is guaranteed to run, so the pending save has to happen
    /// there rather than on a timer that may never fire.
    func flush() {
        autosaveTask?.cancel()
        autosaveTask = nil
        save()
        refresh()
    }

    func refresh() {
        do {
            savedGames = try repository.savedGames()
        } catch {
            lastError = error
        }
    }

    func delete(_ summary: SavedGameSummary) {
        // Deleting the game being played has to stop the autosave too, or the
        // next mutation writes the row straight back.
        if session?.id == summary.id {
            autosaveTask?.cancel()
            autosaveTask = nil
            session?.didChange = nil
            session = nil
            storedPuzzle = nil
        }

        do {
            try repository.deleteSavedGame(puzzleID: summary.id)
        } catch {
            lastError = error
        }
        refresh()
    }

    /// Empties the store, detaching whatever was being played first.
    ///
    /// Order matters: a session left attached would autosave itself back into
    /// the store that was just emptied, which is a confusing way to discover
    /// that "delete everything" did not.
    func eraseEverything() {
        autosaveTask?.cancel()
        autosaveTask = nil
        session?.didChange = nil
        session = nil
        storedPuzzle = nil

        do {
            try repository.deleteAll()
        } catch {
            lastError = error
        }
        refresh()
    }

    // MARK: - Tracking

    private func track(_ session: GameSession, puzzle: StoredPuzzle) {
        // Whatever was being played is finished with first — starting a second
        // game must not drop the first one's last move.
        detach()

        self.session = session
        self.storedPuzzle = puzzle
        // A restored game that is already solved has been recorded before.
        self.hasRecordedCompletion = session.finishedAt != nil
        session.didChange = { [weak self] in self?.sessionDidChange() }
    }

    private func sessionDidChange() {
        guard let session else { return }

        guard session.finishedAt != nil else {
            // Restarting a solved puzzle clears the finish, and the next solve
            // is a genuine second completion.
            hasRecordedCompletion = false
            scheduleAutosave()
            return
        }

        guard !hasRecordedCompletion else { return }
        hasRecordedCompletion = true
        recordCompletion(for: session)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self, autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard let session, let storedPuzzle, session.finishedAt == nil, session.hasProgress else { return }
        do {
            // The puzzle first: a saved game pointing at a puzzle that is not
            // there is unresumable, and this is the only order that cannot leave
            // one behind.
            try repository.save(puzzle: storedPuzzle)
            try repository.save(game: session.savedState)
        } catch {
            lastError = error
        }
    }

    // MARK: - Completion

    private func recordCompletion(for session: GameSession) {
        autosaveTask?.cancel()
        autosaveTask = nil

        let finishedAt = session.finishedAt ?? Date()
        do {
            if let storedPuzzle {
                try repository.save(puzzle: storedPuzzle)
            }

            try repository.record(
                completion: StoredCompletion(
                    puzzleID: session.id,
                    difficulty: session.difficulty,
                    timeSeconds: session.elapsedSeconds,
                    hintsUsed: session.hintsUsed,
                    completedAt: finishedAt
                )
            )

            // After the completion, never before: deleting a saved game also
            // drops the puzzle when nothing refers to it, and the completion is
            // what makes it referred to.
            try repository.deleteSavedGame(puzzleID: session.id)

            session.unlockedAchievements = try evaluateAchievements(
                difficulty: session.difficulty,
                timeSeconds: session.elapsedSeconds,
                at: finishedAt
            )
        } catch {
            lastError = error
        }

        refresh()
    }

    /// What this completion unlocked, persisted and returned in catalogue order.
    ///
    /// Everything is recomputed from the stored history rather than tracked
    /// incrementally: the counts and the streak are then whatever the rows say,
    /// which is the only version that survives a deleted game or a restore.
    private func evaluateAchievements(
        difficulty: Difficulty,
        timeSeconds: Int,
        at date: Date
    ) throws -> [Achievement] {
        let completions = try repository.completions()
        let streak = Streak.compute(completions: completions.map(\.completedAt), now: date)

        let context = Achievements.CompletionContext(
            difficulty: difficulty,
            timeSeconds: timeSeconds,
            // Counted after the insert, so finishing your tenth game is what
            // unlocks `games_10`.
            totalFinished: completions.count,
            currentStreak: streak.current,
            alreadyEarned: try repository.earnedAchievementKeys()
        )

        let keys = Achievements.newlyEarned(context)
        try repository.unlock(achievementKeys: keys, at: date)
        return keys.compactMap(Achievements.achievement(for:))
    }
}
