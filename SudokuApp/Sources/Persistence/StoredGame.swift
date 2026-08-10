import Foundation
import SudokuKit

// The value types the app trades in. Nothing outside `Persistence/` sees a
// `@Model` class or a `ModelContext`.
//
// This is not ceremony. `@Model` classes are reference types tied to the context
// that fetched them, are not `Sendable`, and mutate under you; passing them into
// views makes every one of those properties the view's problem. A snapshot has
// none of them, and it is what lets the repository be swapped for an in-memory
// one in tests without a single conditional in the app.

// MARK: - Puzzle

/// A puzzle as stored: the grid, its solution, and where it came from.
struct StoredPuzzle: Equatable, Sendable, Identifiable {
    let id: UUID
    let puzzle: SudokuKit.Grid
    let solution: SudokuKit.Grid
    let difficulty: Difficulty
    let tier: Tier
    let source: PuzzleSource
    let dateKey: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        puzzle: SudokuKit.Grid,
        solution: SudokuKit.Grid,
        difficulty: Difficulty,
        tier: Tier,
        source: PuzzleSource = .generated,
        dateKey: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.puzzle = puzzle
        self.solution = solution
        self.difficulty = difficulty
        self.tier = tier
        self.source = source
        self.dateKey = dateKey
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        generated: GeneratedPuzzle,
        source: PuzzleSource = .generated,
        dateKey: String? = nil,
        createdAt: Date = Date()
    ) {
        self.init(
            id: id,
            puzzle: generated.puzzle,
            solution: generated.solution,
            difficulty: generated.difficulty,
            tier: generated.tier,
            source: source,
            dateKey: dateKey,
            createdAt: createdAt
        )
    }

    /// The engine's view of the same puzzle.
    var generated: GeneratedPuzzle {
        GeneratedPuzzle(puzzle: puzzle, solution: solution, difficulty: difficulty, tier: tier)
    }
}

// MARK: - Saved game

/// A game in progress, as stored.
struct SavedGameState: Equatable, Sendable {
    let puzzleID: UUID
    let board: SudokuKit.Grid
    /// 81 candidate bitmasks.
    let pencil: [UInt16]
    let elapsedSeconds: Int
    let hintsUsed: Int
    let hintPoints: Int
    let updatedAt: Date

    init(
        puzzleID: UUID,
        board: SudokuKit.Grid,
        pencil: [UInt16],
        elapsedSeconds: Int,
        hintsUsed: Int,
        hintPoints: Int,
        updatedAt: Date = Date()
    ) {
        self.puzzleID = puzzleID
        self.board = board
        self.pencil = pencil
        self.elapsedSeconds = elapsedSeconds
        self.hintsUsed = hintsUsed
        self.hintPoints = hintPoints
        self.updatedAt = updatedAt
    }
}

/// A saved game together with the puzzle it belongs to — what the resume list
/// needs, and what `GameSession` needs to be rebuilt.
struct SavedGameSummary: Equatable, Sendable, Identifiable {
    let puzzle: StoredPuzzle
    let state: SavedGameState

    var id: UUID { puzzle.id }
    var difficulty: Difficulty { puzzle.difficulty }
    var updatedAt: Date { state.updatedAt }

    /// Cells still to fill. Counted from the board rather than stored, so it
    /// cannot disagree with it.
    var remainingCells: Int {
        state.board.emptyCells.count
    }

    /// 0…1, for a progress bar. Measured over the cells the player has to fill,
    /// not all 81 — a puzzle that starts 34/81 filled is 0% done, not 42%.
    var progress: Double {
        let toFill = SudokuKit.Grid.cellCount - puzzle.puzzle.clueCount
        guard toFill > 0 else { return 1 }
        return Double(toFill - remainingCells) / Double(toFill)
    }

    var formattedTime: String {
        String(format: "%d:%02d", state.elapsedSeconds / 60, state.elapsedSeconds % 60)
    }
}

// MARK: - Completion

/// A finished puzzle, as stored. Carries the puzzle reference the engine's
/// `CompletionRecord` has no use for.
struct StoredCompletion: Equatable, Sendable {
    let puzzleID: UUID?
    let difficulty: Difficulty
    let timeSeconds: Int
    let hintsUsed: Int
    let completedAt: Date

    init(
        puzzleID: UUID? = nil,
        difficulty: Difficulty,
        timeSeconds: Int,
        hintsUsed: Int = 0,
        completedAt: Date = Date()
    ) {
        self.puzzleID = puzzleID
        self.difficulty = difficulty
        self.timeSeconds = timeSeconds
        self.hintsUsed = hintsUsed
        self.completedAt = completedAt
    }

    /// The shape `StatsAggregator` and `Streak` consume.
    var record: CompletionRecord {
        CompletionRecord(
            difficulty: difficulty,
            timeSeconds: timeSeconds,
            hintsUsed: hintsUsed,
            completedAt: completedAt
        )
    }
}

// MARK: - Binary encoding

/// Grids and pencil marks are stored as raw bytes rather than as a string or
/// JSON: 81 and 162 bytes exactly, with no parser to get wrong and no format to
/// version. Both decoders validate length and range, and return nil rather than
/// producing a grid that is subtly wrong — a corrupt row should cost a saved
/// game, never a wrong board.
extension SudokuKit.Grid {
    /// 81 bytes, row-major.
    var encoded: Data {
        withUnsafeCells { Data($0) }
    }

    init?(encoded data: Data) {
        guard data.count == SudokuKit.Grid.cellCount else { return nil }
        self.init(values: data.map(Int.init))
    }
}

enum PencilCoding {
    /// 162 bytes: 81 little-endian `UInt16` masks.
    static func encode(_ pencil: [UInt16]) -> Data {
        var data = Data(capacity: pencil.count * 2)
        for mask in pencil {
            data.append(UInt8(truncatingIfNeeded: mask))
            data.append(UInt8(truncatingIfNeeded: mask >> 8))
        }
        return data
    }

    static func decode(_ data: Data) -> [UInt16]? {
        guard data.count == SudokuKit.Grid.cellCount * 2 else { return nil }
        let bytes = [UInt8](data)
        return (0..<SudokuKit.Grid.cellCount).map { index in
            UInt16(bytes[index * 2]) | (UInt16(bytes[index * 2 + 1]) << 8)
        }
    }

    static let empty = [UInt16](repeating: 0, count: SudokuKit.Grid.cellCount)
}

// MARK: - Model ↔ snapshot

extension PuzzleRecord {
    /// Nil when the row cannot be read back as a puzzle — a truncated grid, an
    /// unknown difficulty, a tier outside the ladder. Callers drop it.
    var snapshot: StoredPuzzle? {
        guard
            let id,
            let puzzleData = puzzle, let puzzleGrid = SudokuKit.Grid(encoded: puzzleData),
            let solutionData = solution, let solutionGrid = SudokuKit.Grid(encoded: solutionData),
            let difficultyRaw, let difficulty = Difficulty(rawValue: difficultyRaw),
            let tier, let tierValue = Tier(rawValue: tier)
        else { return nil }

        return StoredPuzzle(
            id: id,
            puzzle: puzzleGrid,
            solution: solutionGrid,
            difficulty: difficulty,
            tier: tierValue,
            source: sourceRaw.flatMap(PuzzleSource.init(rawValue:)) ?? .generated,
            dateKey: dateKey,
            createdAt: createdAt ?? Date()
        )
    }

    func apply(_ snapshot: StoredPuzzle) {
        id = snapshot.id
        puzzle = snapshot.puzzle.encoded
        solution = snapshot.solution.encoded
        difficultyRaw = snapshot.difficulty.rawValue
        tier = snapshot.tier.rawValue
        sourceRaw = snapshot.source.rawValue
        dateKey = snapshot.dateKey
        createdAt = snapshot.createdAt
    }
}

extension SavedGame {
    var snapshot: SavedGameState? {
        guard
            let puzzleID,
            let boardData = board, let boardGrid = SudokuKit.Grid(encoded: boardData)
        else { return nil }

        return SavedGameState(
            puzzleID: puzzleID,
            board: boardGrid,
            // Pencil marks are the one field worth degrading rather than
            // dropping: losing candidate marks is annoying, losing the board is
            // the game.
            pencil: pencil.flatMap(PencilCoding.decode) ?? PencilCoding.empty,
            elapsedSeconds: elapsedSeconds ?? 0,
            hintsUsed: hintsUsed ?? 0,
            hintPoints: hintPoints ?? 0,
            updatedAt: updatedAt ?? Date()
        )
    }

    func apply(_ snapshot: SavedGameState) {
        puzzleID = snapshot.puzzleID
        board = snapshot.board.encoded
        pencil = PencilCoding.encode(snapshot.pencil)
        elapsedSeconds = snapshot.elapsedSeconds
        hintsUsed = snapshot.hintsUsed
        hintPoints = snapshot.hintPoints
        updatedAt = snapshot.updatedAt
    }
}

extension Completion {
    var snapshot: StoredCompletion? {
        guard
            let difficultyRaw, let difficulty = Difficulty(rawValue: difficultyRaw),
            let completedAt
        else { return nil }

        return StoredCompletion(
            puzzleID: puzzleID,
            difficulty: difficulty,
            timeSeconds: timeSeconds ?? 0,
            hintsUsed: hintsUsed ?? 0,
            completedAt: completedAt
        )
    }

    func apply(_ snapshot: StoredCompletion) {
        puzzleID = snapshot.puzzleID
        difficultyRaw = snapshot.difficulty.rawValue
        timeSeconds = snapshot.timeSeconds
        hintsUsed = snapshot.hintsUsed
        completedAt = snapshot.completedAt
    }
}
