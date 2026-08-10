import Foundation
import SudokuKit
import SwiftData
import Testing

@testable import SudokuApp

/// Persistence, headlessly.
///
/// The acceptance criterion for Phase 4 is one sentence — force-quitting
/// mid-game and relaunching restores board, pencil, elapsed time and hint count
/// *exactly* — so that is the test everything else here supports.
@Suite("Persistence")
@MainActor
struct PersistenceTests {

    /// Both implementations are held to the same contract. An in-memory
    /// repository that quietly disagrees with the real one is worse than no
    /// in-memory repository, because every test above it would be testing a
    /// fiction.
    enum RepositoryKind: String, CaseIterable, Sendable {
        case inMemory
        case swiftData
    }

    private func makeRepository(_ kind: RepositoryKind) throws -> any GameRepository {
        switch kind {
        case .inMemory:
            return InMemoryGameRepository()
        case .swiftData:
            let container = try #require(
                SwiftDataRepository.container(inMemory: true),
                "an in-memory model container should always open"
            )
            return SwiftDataRepository(container: container)
        }
    }

    private func puzzle(_ difficulty: Difficulty = .easy, seed: UInt64 = 1) -> GeneratedPuzzle {
        var rng = SeededRandom(seed: seed)
        return Generator.generate(difficulty, using: &rng)
    }

    private func stored(_ difficulty: Difficulty = .easy, seed: UInt64 = 1) -> StoredPuzzle {
        StoredPuzzle(generated: puzzle(difficulty, seed: seed))
    }

    /// Fills `count` cells from the solution, and pencils a couple of marks, so
    /// there is state worth losing.
    private func play(_ session: GameSession, cells count: Int) {
        for cell in session.board.emptyCells.prefix(count) {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
        if let cell = session.board.emptyCells.first {
            session.select(cell)
            session.isPencilMode = true
            session.input(3)
            session.input(7)
            session.isPencilMode = false
        }
    }

    /// Fills the first unit that still has empty cells, from the solution.
    private func complete(unitWithEmptyCellsIn session: GameSession) throws {
        let unit = try #require(
            (0..<Units.count)
                .map { Units.cells(inUnit: $0).map(CellRef.init(index:)) }
                .first { cells in cells.contains { session.board[$0] == 0 } },
            "an unsolved board has a unit with an empty cell in it"
        )
        for cell in unit where session.board[cell] == 0 {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
    }

    private func solve(_ session: GameSession) {
        for cell in session.board.emptyCells {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
    }

    // MARK: - Encoding

    @Test("a grid survives the round trip through 81 bytes")
    func gridEncoding() throws {
        let grid = puzzle().puzzle
        let data = grid.encoded
        #expect(data.count == SudokuKit.Grid.cellCount)
        #expect(SudokuKit.Grid(encoded: data) == grid)
    }

    @Test("a truncated or oversized grid decodes to nothing rather than to a wrong board")
    func gridEncodingRejectsBadLength() {
        #expect(SudokuKit.Grid(encoded: Data(repeating: 0, count: 80)) == nil)
        #expect(SudokuKit.Grid(encoded: Data(repeating: 0, count: 82)) == nil)
        #expect(SudokuKit.Grid(encoded: Data()) == nil)
    }

    @Test("a byte outside 0…9 is not a grid")
    func gridEncodingRejectsBadValues() {
        var bytes = Data(repeating: 0, count: SudokuKit.Grid.cellCount)
        bytes[40] = 11
        #expect(SudokuKit.Grid(encoded: bytes) == nil)
    }

    @Test("pencil masks survive the round trip through 162 bytes")
    func pencilEncoding() throws {
        var pencil = PencilCoding.empty
        pencil[0] = Candidates.all
        pencil[40] = Candidates.bit(9)
        pencil[80] = Candidates.bit(1) | Candidates.bit(5)

        let data = PencilCoding.encode(pencil)
        #expect(data.count == SudokuKit.Grid.cellCount * 2)
        #expect(PencilCoding.decode(data) == pencil)
    }

    @Test("a pencil blob of the wrong length decodes to nothing")
    func pencilEncodingRejectsBadLength() {
        #expect(PencilCoding.decode(Data(repeating: 0, count: 161)) == nil)
        #expect(PencilCoding.decode(Data()) == nil)
    }

    // MARK: - Lifetime

    /// The bug that crashed the app at launch, as a test.
    ///
    /// A `ModelContext` does not keep its `ModelContainer` alive. The repository
    /// originally stored only `container.mainContext`, so the container — a
    /// local in whatever function built the repository — was released
    /// immediately and the *next* fetch trapped. It presented as a bare
    /// `SIGTRAP` at launch with no message and nothing in the log, so the cheap
    /// guard is this: build a repository from a function that hands back nothing
    /// else, then use it.
    @Test("a repository outlives the container reference that built it")
    func repositoryRetainsItsContainer() throws {
        func detached() throws -> any GameRepository {
            let container = try #require(SwiftDataRepository.container(inMemory: true))
            return SwiftDataRepository(container: container)
        }

        let repository = try detached()

        #expect(try repository.savedGames().isEmpty)
        #expect(try repository.completions().isEmpty)
        #expect(try repository.earnedAchievementKeys().isEmpty)

        let puzzle = stored()
        try repository.save(puzzle: puzzle)
        #expect(try repository.puzzle(id: puzzle.id) == puzzle)
    }

    // MARK: - Repository contract

    @Test("a puzzle round-trips", arguments: RepositoryKind.allCases)
    func puzzleRoundTrip(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let puzzle = stored(.medium, seed: 7)
        try repository.save(puzzle: puzzle)

        let loaded = try #require(try repository.puzzle(id: puzzle.id))
        #expect(loaded == puzzle)
        #expect(try repository.puzzle(id: UUID()) == nil)
    }

    @Test("saving the same puzzle twice updates it rather than duplicating it", arguments: RepositoryKind.allCases)
    func puzzleUpsert(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let puzzle = stored()
        try repository.save(puzzle: puzzle)
        try repository.save(puzzle: puzzle)

        try repository.save(game: state(for: puzzle))
        #expect(try repository.savedGames().count == 1)
    }

    @Test("a daily is findable by its date key", arguments: RepositoryKind.allCases)
    func puzzleByDateKey(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let daily = StoredPuzzle(generated: puzzle(), source: .daily, dateKey: "2026-08-10")
        try repository.save(puzzle: daily)

        #expect(try repository.puzzle(dateKey: "2026-08-10")?.id == daily.id)
        #expect(try repository.puzzle(dateKey: "2026-08-11") == nil)
    }

    @Test("a saved game round-trips", arguments: RepositoryKind.allCases)
    func savedGameRoundTrip(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let puzzle = stored()
        try repository.save(puzzle: puzzle)

        let state = state(for: puzzle, elapsed: 754, hintsUsed: 2, hintPoints: 5)
        try repository.save(game: state)

        let loaded = try #require(try repository.savedGame(puzzleID: puzzle.id))
        #expect(loaded == state)
    }

    @Test("saved games come back newest first", arguments: RepositoryKind.allCases)
    func savedGamesOrdering(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let older = stored(.easy, seed: 1)
        let newer = stored(.hard, seed: 2)
        try repository.save(puzzle: older)
        try repository.save(puzzle: newer)

        let now = Date()
        try repository.save(game: state(for: older, updatedAt: now.addingTimeInterval(-600)))
        try repository.save(game: state(for: newer, updatedAt: now))

        #expect(try repository.savedGames().map(\.id) == [newer.id, older.id])
    }

    @Test("a saved game with no puzzle behind it is not offered", arguments: RepositoryKind.allCases)
    func orphanedSavedGameIsHidden(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        // No `save(puzzle:)` — the row references a puzzle that is not there.
        try repository.save(game: state(for: stored()))
        #expect(try repository.savedGames().isEmpty)
    }

    @Test("deleting a saved game takes its puzzle with it", arguments: RepositoryKind.allCases)
    func deleteRemovesUnreferencedPuzzle(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let puzzle = stored()
        try repository.save(puzzle: puzzle)
        try repository.save(game: state(for: puzzle))

        try repository.deleteSavedGame(puzzleID: puzzle.id)

        #expect(try repository.savedGame(puzzleID: puzzle.id) == nil)
        #expect(try repository.puzzle(id: puzzle.id) == nil)
    }

    @Test("a completed puzzle outlives its saved game", arguments: RepositoryKind.allCases)
    func deleteKeepsCompletedPuzzle(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let puzzle = stored()
        try repository.save(puzzle: puzzle)
        try repository.save(game: state(for: puzzle))
        try repository.record(
            completion: StoredCompletion(puzzleID: puzzle.id, difficulty: .easy, timeSeconds: 120)
        )

        try repository.deleteSavedGame(puzzleID: puzzle.id)

        #expect(try repository.savedGame(puzzleID: puzzle.id) == nil)
        #expect(try repository.puzzle(id: puzzle.id) != nil, "the history still points at it")
    }

    @Test("a daily outlives its saved game", arguments: RepositoryKind.allCases)
    func deleteKeepsDaily(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let daily = StoredPuzzle(generated: puzzle(), source: .daily, dateKey: "2026-08-10")
        try repository.save(puzzle: daily)
        try repository.save(game: state(for: daily))

        try repository.deleteSavedGame(puzzleID: daily.id)

        #expect(try repository.puzzle(dateKey: "2026-08-10") != nil)
    }

    @Test("completions come back oldest first", arguments: RepositoryKind.allCases)
    func completionOrdering(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let now = Date()
        try repository.record(
            completion: StoredCompletion(difficulty: .hard, timeSeconds: 900, completedAt: now)
        )
        try repository.record(
            completion: StoredCompletion(
                difficulty: .easy,
                timeSeconds: 60,
                completedAt: now.addingTimeInterval(-86_400)
            )
        )

        #expect(try repository.completions().map(\.difficulty) == [.easy, .hard])
    }

    @Test("unlocking is idempotent", arguments: RepositoryKind.allCases)
    func achievementsAreIdempotent(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        try repository.unlock(achievementKeys: ["first_easy_solve", "games_10"], at: Date())
        try repository.unlock(achievementKeys: ["first_easy_solve"], at: Date())

        #expect(try repository.earnedAchievementKeys() == ["first_easy_solve", "games_10"])
    }

    @Test("deleteAll empties the store", arguments: RepositoryKind.allCases)
    func deleteAll(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let puzzle = stored()
        try repository.save(puzzle: puzzle)
        try repository.save(game: state(for: puzzle))
        try repository.record(completion: StoredCompletion(difficulty: .easy, timeSeconds: 10))
        try repository.unlock(achievementKeys: ["first_easy_solve"], at: Date())

        try repository.deleteAll()

        #expect(try repository.savedGames().isEmpty)
        #expect(try repository.completions().isEmpty)
        #expect(try repository.earnedAchievementKeys().isEmpty)
        #expect(try repository.puzzle(id: puzzle.id) == nil)
    }

    private func state(
        for puzzle: StoredPuzzle,
        elapsed: Int = 0,
        hintsUsed: Int = 0,
        hintPoints: Int = 0,
        updatedAt: Date = Date()
    ) -> SavedGameState {
        SavedGameState(
            puzzleID: puzzle.id,
            board: puzzle.puzzle,
            pencil: PencilCoding.empty,
            elapsedSeconds: elapsed,
            hintsUsed: hintsUsed,
            hintPoints: hintPoints,
            updatedAt: updatedAt
        )
    }

    // MARK: - The acceptance criterion

    @Test("a game restores exactly: board, pencil, elapsed time and hints", arguments: RepositoryKind.allCases)
    func restoresExactly(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)

        // Play a bit, take a hint, let the clock run.
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle())
        play(session, cells: 6)
        for _ in 0..<95 { session.tick() }
        session.hint(at: .reveal)

        // The scene goes inactive: this is what the app does on the way out.
        library.flush()

        // A cold launch: a new library over the same store.
        let relaunched = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let summary = try #require(relaunched.savedGames.first)
        let restored = relaunched.resume(summary)

        #expect(restored.id == session.id)
        #expect(restored.board == session.board)
        #expect(restored.pencil == session.pencil)
        #expect(restored.elapsedSeconds == session.elapsedSeconds)
        #expect(restored.elapsedSeconds == 95)
        #expect(restored.hintsUsed == session.hintsUsed)
        #expect(restored.hintPoints == session.hintPoints)
        #expect(restored.hintPoints > 0)
        #expect(restored.puzzle == session.puzzle)
        #expect(restored.givens == session.givens)
        #expect(!restored.isSolved)
        #expect(relaunched.lastError == nil)
    }

    @Test("a restored game keeps the player's entries editable")
    func restoredEntriesStayEditable() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle())
        let cell = try #require(session.board.emptyCells.first)
        session.select(cell)
        session.input(session.puzzle.solution[cell])
        library.flush()

        let relaunched = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let restored = relaunched.resume(try #require(relaunched.savedGames.first))

        // Givens come from the puzzle, not from whatever is on the board — the
        // easiest way to get this wrong is to derive them from the saved board,
        // which freezes the player's own entries.
        #expect(!restored.isGiven(cell))
        restored.select(cell)
        restored.erase()
        #expect(restored.board[cell] == 0)
    }

    @Test("a restored game does not celebrate work done before the relaunch")
    func restoreDoesNotCelebrate() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle())

        // Complete a whole unit, then save and reload. Which unit is picked has
        // to come from the board rather than from a hardcoded index: a generated
        // puzzle may already have a fully-given row, and completing that one
        // would prove nothing.
        try complete(unitWithEmptyCellsIn: session)
        #expect(!session.celebratingUnits.isEmpty, "completing a unit should celebrate the first time")
        library.flush()

        let relaunched = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let restored = relaunched.resume(try #require(relaunched.savedGames.first))
        #expect(restored.celebratingUnits.isEmpty, "yesterday's work is not an achievement today")

        // And the next unit completed after the restore still celebrates: the
        // baseline is recorded at load, not on the first move after it.
        try complete(unitWithEmptyCellsIn: restored)
        #expect(!restored.celebratingUnits.isEmpty)
    }

    // MARK: - Autosave

    @Test("autosave waits for the debounce, then writes")
    func autosaveDebounces() async throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(50))
        let session = library.start(puzzle())

        play(session, cells: 1)
        #expect(try repository.savedGame(puzzleID: session.id) == nil, "not straight away")

        try await Task.sleep(for: .milliseconds(300))
        #expect(try repository.savedGame(puzzleID: session.id) != nil, "but shortly afterwards")
    }

    @Test("a run of moves collapses into one write")
    func autosaveCoalesces() async throws {
        let repository = CountingRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(50))
        let session = library.start(puzzle())

        play(session, cells: 8)
        try await Task.sleep(for: .milliseconds(300))

        #expect(repository.savedGameWrites == 1)
    }

    @Test("a game nobody has played is not saved")
    func untouchedGameIsNotSaved() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle())

        // Tapped a difficulty, looked at the board, left. The clock ran, but
        // nothing happened — this should leave no trace at all.
        for _ in 0..<30 { session.tick() }
        library.flush()

        #expect(library.savedGames.isEmpty)
        #expect(try repository.puzzle(id: session.id) == nil, "and no orphaned puzzle either")
    }

    @Test("flushing writes immediately rather than waiting for the debounce")
    func flushIsImmediate() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .seconds(600))
        let session = library.start(puzzle())
        play(session, cells: 2)

        library.flush()

        #expect(try repository.savedGame(puzzleID: session.id) != nil)
        #expect(library.savedGames.count == 1)
    }

    @Test("starting a second game saves the first one on the way out")
    func startingAnotherGameSavesTheFirst() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .seconds(600))

        let first = library.start(puzzle(.easy, seed: 1))
        play(first, cells: 3)
        let second = library.start(puzzle(.hard, seed: 2))
        play(second, cells: 1)
        library.flush()

        #expect(try repository.savedGame(puzzleID: first.id) != nil)
        #expect(library.savedGames.count == 2)
    }

    @Test("a deleted game stays deleted, even the one on screen")
    func deletingTheLiveGameStopsAutosave() async throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(20))
        let session = library.start(puzzle())
        play(session, cells: 2)
        library.flush()

        let summary = try #require(library.savedGames.first)
        library.delete(summary)
        #expect(library.savedGames.isEmpty)

        // The detached session keeps working — it just no longer writes.
        play(session, cells: 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try repository.savedGame(puzzleID: session.id) == nil)
        #expect(library.savedGames.isEmpty)
    }

    // MARK: - Completion

    @Test("solving records the completion and clears the saved game", arguments: RepositoryKind.allCases)
    func solvingRecordsACompletion(kind: RepositoryKind) throws {
        let repository = try makeRepository(kind)
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle(.easy))

        for _ in 0..<200 { session.tick() }
        solve(session)

        #expect(session.isSolved)
        let completions = try repository.completions()
        #expect(completions.count == 1)
        #expect(completions.first?.difficulty == .easy)
        #expect(completions.first?.timeSeconds == 200)
        #expect(completions.first?.puzzleID == session.id)

        #expect(try repository.savedGame(puzzleID: session.id) == nil, "a finished game is not in progress")
        #expect(library.savedGames.isEmpty)
        #expect(try repository.puzzle(id: session.id) != nil, "but the puzzle stays, for the history")
        #expect(library.lastError == nil)
    }

    @Test("a first easy solve unlocks its achievements, once")
    func solvingUnlocksAchievements() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))

        let first = library.start(puzzle(.easy, seed: 1))
        solve(first)

        #expect(first.unlockedAchievements.map(\.key) == ["first_easy_solve", "speed_easy_5m"])
        #expect(try repository.earnedAchievementKeys() == ["first_easy_solve", "speed_easy_5m"])

        // The second easy solve unlocks nothing: both are firsts, and a first
        // only happens once.
        let second = library.start(puzzle(.easy, seed: 2))
        solve(second)

        #expect(second.unlockedAchievements.isEmpty)
        #expect(try repository.completions().count == 2)
        #expect(try repository.earnedAchievementKeys() == ["first_easy_solve", "speed_easy_5m"])
    }

    @Test("expert counts as hard for achievements")
    func expertMapsOntoHard() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle(.expert))
        solve(session)

        #expect(try repository.earnedAchievementKeys().contains("first_hard_solve"))
    }

    @Test("solving the same puzzle twice records it twice")
    func restartAndSolveAgain() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle())

        solve(session)
        session.restart()
        solve(session)

        #expect(try repository.completions().count == 2)
    }

    @Test("the completion is what the streak and the stats are computed from")
    func completionsFeedTheEngine() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
        let session = library.start(puzzle(.medium))
        solve(session)

        let records = try repository.completionRecords()
        #expect(records.count == 1)
        let stats = StatsAggregator.aggregate(records)
        #expect(stats.totalFinished == 1)
        #expect(stats.byDifficulty[.medium] == 1)
        #expect(stats.streak.current == 1)
    }
}

// MARK: - Counting repository

/// Counts writes, to prove the debounce coalesces rather than merely delays.
@MainActor
private final class CountingRepository: GameRepository {
    private let backing = InMemoryGameRepository()
    private(set) var savedGameWrites = 0

    func save(puzzle: StoredPuzzle) throws { try backing.save(puzzle: puzzle) }
    func puzzle(id: UUID) throws -> StoredPuzzle? { try backing.puzzle(id: id) }
    func puzzle(dateKey: String) throws -> StoredPuzzle? { try backing.puzzle(dateKey: dateKey) }
    func dailyPuzzles() throws -> [StoredPuzzle] { try backing.dailyPuzzles() }

    func save(game state: SavedGameState) throws {
        savedGameWrites += 1
        try backing.save(game: state)
    }

    func savedGame(puzzleID: UUID) throws -> SavedGameState? { try backing.savedGame(puzzleID: puzzleID) }
    func savedGames() throws -> [SavedGameSummary] { try backing.savedGames() }
    func deleteSavedGame(puzzleID: UUID) throws { try backing.deleteSavedGame(puzzleID: puzzleID) }
    func record(completion: StoredCompletion) throws { try backing.record(completion: completion) }
    func completions() throws -> [StoredCompletion] { try backing.completions() }
    func achievementUnlocks() throws -> [String: Date] { try backing.achievementUnlocks() }
    func unlock(achievementKeys keys: [String], at date: Date) throws {
        try backing.unlock(achievementKeys: keys, at: date)
    }
    func deleteAll() throws { try backing.deleteAll() }
}
