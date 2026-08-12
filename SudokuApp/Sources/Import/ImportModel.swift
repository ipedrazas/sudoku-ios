import Foundation
import SudokuKit

/// Typing a puzzle in, and deciding whether it is one.
///
/// The web app checked an imported grid for uniqueness and stopped there. This
/// also *rates* it, which the engine can do for free and which answers the
/// question the player actually has — not "is this legal" but "what am I in
/// for".
@Observable
@MainActor
final class ImportModel {

    /// What is wrong with the grid, or what it turned out to be.
    enum Status: Equatable, Sendable {
        /// Fewer than the 17 clues any uniquely-solvable Sudoku needs.
        case tooFewClues(clues: Int)
        /// A digit repeats in a row, column or box.
        case breaksRules
        /// Legal so far, but no arrangement completes it.
        case unsolvable
        /// More than one solution: not a puzzle, a family of them.
        case notUnique
        /// Good, and here is what it is.
        case ready(tier: Tier, clues: Int)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    private(set) var grid = SudokuKit.Grid()
    private(set) var status: Status = .tooFewClues(clues: 0)
    /// Cells that repeat a digit, for the grid to mark.
    private(set) var conflicts: Set<CellRef> = []
    var selection: CellRef?

    /// **17 is not a style choice.** It is the proven minimum number of clues a
    /// Sudoku with a unique solution can have (McGuire, Tugemann & Civario,
    /// 2012), so anything below it cannot be a puzzle and there is no point
    /// asking the solver.
    static let minimumClues = 17

    init(grid: SudokuKit.Grid = SudokuKit.Grid()) {
        self.grid = grid
        validate()
    }

    // MARK: - Editing

    func select(_ cell: CellRef) {
        selection = selection == cell ? nil : cell
    }

    func input(_ digit: Int) {
        guard let selection, (1...SudokuKit.Grid.size).contains(digit) else { return }
        // Typing the digit that is already there clears it, exactly as it does
        // in a game — the same key writes and undoes.
        grid[selection] = grid[selection] == digit ? 0 : digit
        validate()
    }

    func erase() {
        guard let selection, grid[selection] != 0 else { return }
        grid[selection] = 0
        validate()
    }

    func clear() {
        grid = SudokuKit.Grid()
        selection = nil
        validate()
    }

    /// Accepts a pasted 81-character grid, in the canonical form the rest of the
    /// app already speaks. Anything else is ignored rather than half-applied.
    @discardableResult
    func paste(_ text: String) -> Bool {
        let trimmed = text.filter { !$0.isWhitespace }
        guard let parsed = SudokuKit.Grid(digits: trimmed) else { return false }
        grid = parsed
        selection = nil
        validate()
        return true
    }

    // MARK: - Validation

    /// Cheap enough to run on every keystroke.
    ///
    /// The order matters: rule conflicts first because they are free and
    /// specific, then the clue floor, and only then the solver — which is asked
    /// for at most two solutions, so it stops as soon as the answer is "more
    /// than one" rather than counting them all.
    func validate() {
        conflicts = Validator.conflicts(in: grid)
        guard conflicts.isEmpty else {
            status = .breaksRules
            return
        }

        let clues = grid.clueCount
        guard clues >= Self.minimumClues else {
            status = .tooFewClues(clues: clues)
            return
        }

        switch Solver.countSolutions(grid, limit: 2) {
        case 0: status = .unsolvable
        case 1: status = .ready(tier: Rater.rate(grid), clues: clues)
        default: status = .notUnique
        }
    }

    /// The puzzle, once it is one.
    ///
    /// The solution is computed here rather than left for later because
    /// everything downstream assumes it exists: mistake detection is a diff
    /// against it, and a hint without it has nothing to check.
    func generatedPuzzle() -> GeneratedPuzzle? {
        guard case .ready(let tier, _) = status, let solution = Solver.solve(grid) else { return nil }
        return GeneratedPuzzle(
            puzzle: grid,
            solution: solution,
            difficulty: Self.difficulty(for: tier),
            tier: tier
        )
    }

    /// The rung an imported puzzle would have been generated as.
    ///
    /// A rating is a technique, and the ladder is defined by technique, so this
    /// is a lookup rather than a judgement. `.beyond` has no rung — it is the
    /// tier that means "needs something this engine cannot do" — and it maps to
    /// expert so the puzzle stays playable, with the screen saying plainly that
    /// hints may run out.
    nonisolated static func difficulty(for tier: Tier) -> Difficulty {
        switch tier {
        case .nakedSingle, .hiddenSingle: .easy
        case .locked: .medium
        case .advanced: .hard
        case .beyond: .expert
        }
    }

    /// What the rating means, in the vocabulary the hints use.
    nonisolated static func describe(_ tier: Tier) -> String {
        switch tier {
        case .nakedSingle: String(localized: "Scanning alone will finish it.")
        case .hiddenSingle: String(localized: "Needs hidden singles — scanning, with a little care.")
        case .locked: String(localized: "Needs locked candidates or a naked pair.")
        case .advanced: String(localized: "Needs a hidden pair, naked triple, or X-wing.")
        case .beyond:
            String(localized: "Harder than anything this app generates. Hints may run out before the puzzle does.")
        }
    }
}
