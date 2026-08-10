import Foundation
import SudokuKit

/// Everything the app stores, behind one protocol.
///
/// Views never touch a `ModelContext`; they go through this. Two implementations
/// exist — SwiftData for the app, in-memory for tests and as the fallback when
/// the store cannot be opened — and a sync provider could be a third without any
/// caller changing.
///
/// `@MainActor` rather than an actor: a `ModelContext` is not `Sendable`, and
/// the alternative (a background context with its own queue) buys nothing here.
/// Every write is at most 250 bytes and every read is a handful of rows, so the
/// main thread is the right place for it, and staying there keeps the whole
/// layer free of concurrency ceremony.
@MainActor
protocol GameRepository: AnyObject {

    // MARK: Puzzles

    /// Inserts the puzzle, or updates the row with the same `id`.
    func save(puzzle: StoredPuzzle) throws
    func puzzle(id: UUID) throws -> StoredPuzzle?
    /// The stored daily for a `"YYYY-MM-DD"` key, if it has been generated.
    func puzzle(dateKey: String) throws -> StoredPuzzle?

    // MARK: Games in progress

    /// Inserts or replaces the saved game for `state.puzzleID`.
    func save(game state: SavedGameState) throws
    func savedGame(puzzleID: UUID) throws -> SavedGameState?
    /// Every game in progress, most recently played first.
    func savedGames() throws -> [SavedGameSummary]
    func deleteSavedGame(puzzleID: UUID) throws

    // MARK: History

    func record(completion: StoredCompletion) throws
    /// Every completion, oldest first.
    func completions() throws -> [StoredCompletion]

    // MARK: Achievements

    func earnedAchievementKeys() throws -> Set<String>
    /// Unlocks keys that are not already unlocked. Idempotent.
    func unlock(achievementKeys keys: [String], at date: Date) throws

    // MARK: Maintenance

    /// Empties the store. Used by the `-resetStore` launch argument so a UI test
    /// starts from nothing, and the operation a "delete all data" setting needs.
    func deleteAll() throws
}

extension GameRepository {
    /// Completions in the shape `StatsAggregator` and `Streak` consume.
    func completionRecords() throws -> [CompletionRecord] {
        try completions().map(\.record)
    }
}

// MARK: - In-memory

/// A repository that forgets everything on deallocation.
///
/// Two jobs. It is what the tests run against, and it is what the app falls back
/// to when the SwiftData store cannot be opened — a corrupt store should cost
/// history, not the ability to play.
@MainActor
final class InMemoryGameRepository: GameRepository {
    private var puzzles: [UUID: StoredPuzzle] = [:]
    private var games: [UUID: SavedGameState] = [:]
    private var history: [StoredCompletion] = []
    private var achievements: [String: Date] = [:]

    init() {}

    func save(puzzle: StoredPuzzle) throws {
        puzzles[puzzle.id] = puzzle
    }

    func puzzle(id: UUID) throws -> StoredPuzzle? {
        puzzles[id]
    }

    func puzzle(dateKey: String) throws -> StoredPuzzle? {
        puzzles.values.first { $0.dateKey == dateKey }
    }

    func save(game state: SavedGameState) throws {
        games[state.puzzleID] = state
    }

    func savedGame(puzzleID: UUID) throws -> SavedGameState? {
        games[puzzleID]
    }

    func savedGames() throws -> [SavedGameSummary] {
        games.values
            .compactMap { state in
                puzzles[state.puzzleID].map { SavedGameSummary(puzzle: $0, state: state) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSavedGame(puzzleID: UUID) throws {
        games[puzzleID] = nil
        if !isPuzzleStillNeeded(puzzleID) {
            puzzles[puzzleID] = nil
        }
    }

    func record(completion: StoredCompletion) throws {
        history.append(completion)
        history.sort { $0.completedAt < $1.completedAt }
    }

    func completions() throws -> [StoredCompletion] {
        history
    }

    func earnedAchievementKeys() throws -> Set<String> {
        Set(achievements.keys)
    }

    func unlock(achievementKeys keys: [String], at date: Date) throws {
        for key in keys where achievements[key] == nil {
            achievements[key] = date
        }
    }

    func deleteAll() throws {
        puzzles.removeAll()
        games.removeAll()
        history.removeAll()
        achievements.removeAll()
    }

    /// A puzzle outlives its saved game when something still refers to it: a
    /// completion in the history, or a date key that makes it a daily.
    private func isPuzzleStillNeeded(_ id: UUID) -> Bool {
        if puzzles[id]?.dateKey != nil { return true }
        return history.contains { $0.puzzleID == id }
    }
}
