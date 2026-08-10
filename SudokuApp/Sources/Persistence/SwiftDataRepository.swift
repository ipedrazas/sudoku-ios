import Foundation
import SudokuKit
import SwiftData

/// The real store.
///
/// Reads fetch the whole table and filter in Swift rather than using
/// `#Predicate`. That is a deliberate call, not laziness: every model property
/// is optional for CloudKit's sake (§6.2), and predicates over optional
/// properties are the sharp edge of SwiftData — several forms compile and then
/// fail at run time. The tables here are tiny (a handful of puzzles, one row per
/// finished game) so the cost is a rounding error, and the behaviour is
/// something the type checker can actually verify.
@MainActor
final class SwiftDataRepository: GameRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    /// The app's store, or nil if it cannot be opened.
    ///
    /// A store that fails to open is not a reason to refuse to run: the caller
    /// falls back to `InMemoryGameRepository` and the player gets a game without
    /// a history rather than a crash on launch.
    static func container(inMemory: Bool = false) -> ModelContainer? {
        let schema = Schema(SchemaV1.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try? ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Puzzles

    func save(puzzle: StoredPuzzle) throws {
        let record: PuzzleRecord
        if let existing = try existingPuzzleRecord(id: puzzle.id) {
            record = existing
        } else {
            record = PuzzleRecord()
            context.insert(record)
        }
        record.apply(puzzle)
        try context.save()
    }

    func puzzle(id: UUID) throws -> StoredPuzzle? {
        try existingPuzzleRecord(id: id)?.snapshot
    }

    func puzzle(dateKey: String) throws -> StoredPuzzle? {
        try context.fetch(FetchDescriptor<PuzzleRecord>())
            .first { $0.dateKey == dateKey }?
            .snapshot
    }

    // MARK: - Games in progress

    func save(game state: SavedGameState) throws {
        let record: SavedGame
        if let existing = try existingSavedGame(puzzleID: state.puzzleID) {
            record = existing
        } else {
            record = SavedGame()
            context.insert(record)
        }
        record.apply(state)
        try context.save()
    }

    func savedGame(puzzleID: UUID) throws -> SavedGameState? {
        try existingSavedGame(puzzleID: puzzleID)?.snapshot
    }

    func savedGames() throws -> [SavedGameSummary] {
        let puzzles = try context.fetch(FetchDescriptor<PuzzleRecord>())
            .compactMap(\.snapshot)
            .reduce(into: [UUID: StoredPuzzle]()) { $0[$1.id] = $1 }

        // A saved game whose puzzle is missing or unreadable is not resumable,
        // so it is dropped from the list rather than shown as a row that fails
        // when tapped.
        return try context.fetch(FetchDescriptor<SavedGame>())
            .compactMap(\.snapshot)
            .compactMap { state in
                puzzles[state.puzzleID].map { SavedGameSummary(puzzle: $0, state: state) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSavedGame(puzzleID: UUID) throws {
        if let record = try existingSavedGame(puzzleID: puzzleID) {
            context.delete(record)
        }
        if let record = try existingPuzzleRecord(id: puzzleID), try !isPuzzleStillNeeded(record) {
            context.delete(record)
        }
        try context.save()
    }

    // MARK: - History

    func record(completion: StoredCompletion) throws {
        let record = Completion()
        record.apply(completion)
        context.insert(record)
        try context.save()
    }

    func completions() throws -> [StoredCompletion] {
        try context.fetch(FetchDescriptor<Completion>())
            .compactMap(\.snapshot)
            .sorted { $0.completedAt < $1.completedAt }
    }

    // MARK: - Achievements

    func earnedAchievementKeys() throws -> Set<String> {
        let records = try context.fetch(FetchDescriptor<AchievementRecord>())
        return Set(records.compactMap(\.key))
    }

    func unlock(achievementKeys keys: [String], at date: Date) throws {
        let earned = try earnedAchievementKeys()
        var inserted = false
        for key in keys where !earned.contains(key) {
            context.insert(AchievementRecord(key: key, unlockedAt: date))
            inserted = true
        }
        if inserted { try context.save() }
    }

    // MARK: - Maintenance

    func deleteAll() throws {
        try context.delete(model: SavedGame.self)
        try context.delete(model: Completion.self)
        try context.delete(model: AchievementRecord.self)
        try context.delete(model: PuzzleRecord.self)
        try context.save()
    }

    // MARK: - Lookups

    private func existingPuzzleRecord(id: UUID) throws -> PuzzleRecord? {
        try context.fetch(FetchDescriptor<PuzzleRecord>()).first { $0.id == id }
    }

    private func existingSavedGame(puzzleID: UUID) throws -> SavedGame? {
        try context.fetch(FetchDescriptor<SavedGame>()).first { $0.puzzleID == puzzleID }
    }

    /// A daily is kept for its date key, and any puzzle with a completion is
    /// kept so the history keeps pointing at something real.
    private func isPuzzleStillNeeded(_ record: PuzzleRecord) throws -> Bool {
        if record.dateKey != nil { return true }
        let id = record.id
        return try context.fetch(FetchDescriptor<Completion>()).contains { $0.puzzleID == id }
    }
}
