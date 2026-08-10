import Foundation
import SudokuKit

/// The state of one puzzle in progress.
///
/// This is the tracer-bullet form: enough to select a cell and place a digit,
/// with the shape the full session will grow into. Phase 3 adds pencil marks,
/// undo/redo, the timer, blind mode, hints and both input orders — see P3-1.
///
/// `SudokuKit.Grid` is spelled out wherever it appears: SwiftUI has a `Grid`
/// view, and an unqualified `Grid` in a file that imports both is ambiguous.
@Observable
@MainActor
final class GameSession {
    /// The puzzle as dealt, kept so the board can be restarted and so hints have
    /// a solution to check against.
    let puzzle: GeneratedPuzzle

    /// The player's board: givens plus whatever they have entered.
    private(set) var board: SudokuKit.Grid

    /// Which cells came with the puzzle. Givens are immutable.
    let givens: [Bool]

    var selection: CellRef?

    init(puzzle: GeneratedPuzzle) {
        self.puzzle = puzzle
        self.board = puzzle.puzzle
        self.givens = (0..<SudokuKit.Grid.cellCount).map { puzzle.puzzle[$0] != 0 }
    }

    var difficulty: Difficulty { puzzle.difficulty }

    func isGiven(_ cell: CellRef) -> Bool { givens[cell.index] }

    // MARK: - Intents

    /// Selects a cell, or deselects it if it was already selected.
    ///
    /// Tapping the selected cell to clear it is web parity
    /// (`useGameBoard.ts:248-254`) and matters more on touch, where there is no
    /// other way to dismiss a selection.
    func select(_ cell: CellRef) {
        selection = selection == cell ? nil : cell
    }

    /// Places a digit in the selected cell.
    ///
    /// Entering the digit already there erases it, so the same key both writes
    /// and undoes — again web parity (`useGameBoard.ts:286-289`), and the
    /// behaviour a player expects when they mistype.
    func input(_ digit: Int) {
        guard let cell = selection, !isGiven(cell) else { return }
        board[cell] = board[cell] == digit ? 0 : digit
    }

    func erase() {
        guard let cell = selection, !isGiven(cell) else { return }
        board[cell] = 0
    }

    func restart() {
        board = puzzle.puzzle
        selection = nil
    }

    // MARK: - Derived

    /// Cells that duplicate a value in their row, column or box.
    var conflicts: Set<CellRef> {
        Validator.conflicts(in: board)
    }

    /// How many of each digit are still to be placed, indexed 1…9.
    var remainingCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for digit in 1...SudokuKit.Grid.size { counts[digit] = SudokuKit.Grid.size }
        for index in 0..<SudokuKit.Grid.cellCount {
            let value = board[index]
            guard value != 0 else { continue }
            counts[value, default: 0] -= 1
        }
        return counts
    }

    /// Computed locally, so a solve registers with no server and no network —
    /// the web app does the same (`useGameBoard.ts:78-81`).
    var isSolved: Bool {
        Validator.isSolved(board)
    }
}
