import Foundation
import SudokuKit

/// How a player places digits.
enum InputMode: String, CaseIterable, Sendable {
    /// Tap a cell, then a digit. Web parity.
    case cellFirst
    /// Tap a digit to arm it, then tap cells. Faster for filling many of the
    /// same digit, and what most competitive Sudoku apps default to.
    case digitFirst

    var name: String {
        switch self {
        case .cellFirst: "Cell first"
        case .digitFirst: "Digit first"
        }
    }
}

/// The state of one puzzle in progress.
///
/// Replaces the web app's `useGameBoard` + `useGameTimer` + `useGamePersistence`
/// (`frontend/src/hooks/`). It owns the board, pencil marks, selection, modes,
/// undo history and timer, exposes intent methods, and publishes derived values.
///
/// `SudokuKit.Grid` is spelled out wherever it appears: SwiftUI has a `Grid`
/// view, and an unqualified `Grid` in a file that imports both is ambiguous.
@Observable
@MainActor
final class GameSession {

    // MARK: - Puzzle

    /// The puzzle as dealt, kept so the board can be restarted and so hints have
    /// a solution to check against.
    let puzzle: GeneratedPuzzle

    private(set) var board: SudokuKit.Grid

    /// Which cells came with the puzzle. Givens are immutable.
    let givens: [Bool]

    /// Candidate marks per cell, as `UInt16` bitmasks — the same representation
    /// the solver uses, so nothing converts at the hint boundary.
    private(set) var pencil: [UInt16]

    // MARK: - Interaction state

    var selection: CellRef?
    var inputMode: InputMode = .cellFirst
    /// The digit armed in digit-first mode.
    private(set) var armedDigit: Int?
    var isPencilMode = false
    /// Masks the selected cell's row and column — a self-imposed difficulty aid.
    private(set) var isBlindMode = false
    /// Lights up every cell holding this digit.
    private(set) var highlightedDigit: Int?
    var showsConflicts: Bool

    // MARK: - Progress

    private(set) var elapsed: Duration = .zero
    private(set) var isPaused = false
    private(set) var hintPoints = 0
    private(set) var hintsUsed = 0
    private(set) var finishedAt: Date?

    /// Units that just became correctly complete, for the celebration.
    private(set) var celebratingUnits: Set<UnitRef> = []

    /// Bumped on every board or pencil mutation. Derived values memoise against
    /// it so a redraw does not re-derive conflicts for the whole grid.
    private(set) var version = 0

    // MARK: - History

    private struct Snapshot {
        let board: SudokuKit.Grid
        let pencil: [UInt16]
    }

    /// Capped at 100, matching the web app (`useGameBoard.ts:182`). A deeper
    /// history is not worth the memory on a puzzle with 81 cells.
    private static let historyLimit = 100
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Init

    init(puzzle: GeneratedPuzzle, showsConflicts: Bool = false) {
        self.puzzle = puzzle
        self.board = puzzle.puzzle
        self.givens = (0..<SudokuKit.Grid.cellCount).map { puzzle.puzzle[$0] != 0 }
        self.pencil = [UInt16](repeating: 0, count: SudokuKit.Grid.cellCount)
        self.showsConflicts = showsConflicts
    }

    var difficulty: Difficulty { puzzle.difficulty }

    func isGiven(_ cell: CellRef) -> Bool { givens[cell.index] }

    // MARK: - Selection

    /// Selects a cell — or, in digit-first mode with a digit armed, places it.
    ///
    /// Tapping the selected cell to clear it is web parity
    /// (`useGameBoard.ts:248-254`) and matters more on touch, where there is no
    /// other way to dismiss a selection. Any selection also cancels blind mode,
    /// since the mask is anchored to the previously selected cell.
    func select(_ cell: CellRef) {
        isBlindMode = false

        if inputMode == .digitFirst, let digit = armedDigit {
            selection = cell
            place(digit, at: cell)
            return
        }

        selection = selection == cell ? nil : cell
    }

    /// Long-press: masks the selected cell's row and column.
    ///
    /// Only meaningful on a filled cell, matching the web app
    /// (`useGameBoard.ts:256-264`).
    func longPress(_ cell: CellRef) {
        guard board[cell] != 0 else { return }
        selection = cell
        isBlindMode.toggle()
    }

    /// Double-tap: highlights every cell holding this cell's digit.
    func doubleTap(_ cell: CellRef) {
        let value = board[cell]
        guard value != 0 else { return }
        highlightedDigit = highlightedDigit == value ? nil : value
    }

    /// Arms a digit in digit-first mode, and highlights it either way.
    func armDigit(_ digit: Int) {
        armedDigit = armedDigit == digit ? nil : digit
        highlightedDigit = armedDigit
    }

    func clearHighlight() {
        highlightedDigit = nil
        armedDigit = nil
    }

    // MARK: - Input

    /// Places a digit, or toggles a pencil mark when notes are on.
    ///
    /// In digit-first mode this arms the digit instead; cells are filled by
    /// tapping them afterwards.
    func input(_ digit: Int) {
        guard (1...SudokuKit.Grid.size).contains(digit) else { return }

        if inputMode == .digitFirst {
            armDigit(digit)
            return
        }
        guard let cell = selection else { return }
        place(digit, at: cell)
    }

    /// One-shot pencil entry: a long-press on a numpad key marks a candidate
    /// without leaving normal mode.
    func inputNote(_ digit: Int) {
        guard let cell = selection, !isGiven(cell), board[cell] == 0 else { return }
        mutate { pencil[cell.index] ^= Candidates.bit(digit) }
    }

    private func place(_ digit: Int, at cell: CellRef) {
        guard !isGiven(cell) else { return }

        if isPencilMode {
            // A cell that already holds a value cannot also hold candidates.
            guard board[cell] == 0 else { return }
            mutate { pencil[cell.index] ^= Candidates.bit(digit) }
            return
        }

        mutate {
            // Entering the digit already there erases it, so the same key both
            // writes and undoes (`useGameBoard.ts:286-289`).
            board[cell] = board[cell] == digit ? 0 : digit
            // Placing a value clears that cell's candidates (l.293-297).
            pencil[cell.index] = 0
        }
    }

    func erase() {
        guard let cell = selection, !isGiven(cell) else { return }
        guard board[cell] != 0 || pencil[cell.index] != 0 else { return }
        mutate {
            board[cell] = 0
            pencil[cell.index] = 0
        }
    }

    func toggleNotes() {
        isPencilMode.toggle()
    }

    /// Fills every empty cell's candidates from the rules.
    ///
    /// A convenience the web app does not have; it saves the tedium of marking
    /// up a fresh grid by hand without revealing anything a player could not
    /// work out.
    func autoFillNotes() {
        let candidates = CandidateGrid(board)
        mutate {
            for index in 0..<SudokuKit.Grid.cellCount where board[index] == 0 {
                pencil[index] = candidates[index]
            }
        }
    }

    // MARK: - History

    /// Applies a mutation, recording an undo snapshot first.
    ///
    /// Every mutation goes through here, which is what keeps undo honest: there
    /// is no path that changes the board without pushing history.
    private func mutate(_ change: () -> Void) {
        undoStack.append(Snapshot(board: board, pencil: pencil))
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        // Any new move invalidates the redo branch (`useGameBoard.ts:194`).
        redoStack.removeAll()

        change()
        boardDidChange()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(board: board, pencil: pencil))
        apply(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(board: board, pencil: pencil))
        apply(snapshot)
    }

    private func apply(_ snapshot: Snapshot) {
        board = snapshot.board
        pencil = snapshot.pencil
        boardDidChange()
    }

    func restart() {
        board = puzzle.puzzle
        pencil = [UInt16](repeating: 0, count: SudokuKit.Grid.cellCount)
        selection = nil
        armedDigit = nil
        highlightedDigit = nil
        isBlindMode = false
        isPencilMode = false
        hintPoints = 0
        hintsUsed = 0
        finishedAt = nil
        elapsed = .zero
        undoStack.removeAll()
        redoStack.removeAll()
        completedUnits = nil
        celebratingUnits = []
        boardDidChange()
    }

    // MARK: - Hints

    /// The next hint for the current board.
    ///
    /// Charging only the delta means a player who works up from a nudge is never
    /// worse off than one who jumps straight to the answer.
    @discardableResult
    func hint(at level: HintLevel, previousLevel: HintLevel? = nil) -> Hint {
        let hint = HintEngine.hint(for: board, solution: puzzle.solution)
        let charged = level.cost - (previousLevel?.cost ?? 0)
        hintPoints += max(0, charged)
        if level == .reveal { hintsUsed += 1 }
        return hint
    }

    /// Applies a hint's placement, if it has one.
    func applyHint(_ hint: Hint) {
        guard let placement = hint.placement, placement.digit != 0 else { return }
        mutate {
            board[placement.cell] = placement.digit
            pencil[placement.cell.index] = 0
        }
        selection = placement.cell
    }

    // MARK: - Timer

    /// Advances the clock. Driven by the view's timer so the session stays
    /// testable without waiting on wall-clock time.
    func tick(_ interval: Duration = .seconds(1)) {
        guard !isPaused, finishedAt == nil else { return }
        elapsed += interval
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func togglePause() { isPaused.toggle() }

    var elapsedSeconds: Int { Int(elapsed.components.seconds) }

    var formattedTime: String {
        let total = elapsedSeconds
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Derived

    private var cachedVersion = -1
    private var cachedConflicts: Set<CellRef> = []
    private var cachedRemaining: [Int: Int] = [:]
    private var completedUnits: Set<UnitRef>?

    /// Cells duplicating a value in their row, column or box.
    ///
    /// Empty when the setting is off — the web app makes error highlighting
    /// opt-in (`lib/settings.ts:36`), and defaulting it on would decide for the
    /// player how much help they want.
    var conflicts: Set<CellRef> {
        guard showsConflicts else { return [] }
        refreshDerivedIfNeeded()
        return cachedConflicts
    }

    /// How many of each digit remain to be placed, indexed 1…9.
    var remainingCounts: [Int: Int] {
        refreshDerivedIfNeeded()
        return cachedRemaining
    }

    private func refreshDerivedIfNeeded() {
        guard cachedVersion != version else { return }
        cachedVersion = version

        cachedConflicts = Validator.conflicts(in: board)

        var counts: [Int: Int] = [:]
        for digit in 1...SudokuKit.Grid.size { counts[digit] = SudokuKit.Grid.size }
        for index in 0..<SudokuKit.Grid.cellCount {
            let value = board[index]
            guard value != 0 else { continue }
            counts[value, default: 0] -= 1
        }
        cachedRemaining = counts
    }

    /// Cells masked by blind mode: the selected cell's row and column.
    var blindedCells: Set<CellRef> {
        guard isBlindMode, let selection else { return [] }
        var masked = Set<CellRef>()
        for index in 0..<SudokuKit.Grid.size {
            masked.insert(CellRef(row: selection.row, col: index))
            masked.insert(CellRef(row: index, col: selection.col))
        }
        masked.remove(selection)
        return masked
    }

    /// Whether a cell should light up for the highlighted digit — either because
    /// it holds that digit, or because it is pencilled as a candidate.
    func isHighlighted(_ cell: CellRef) -> Bool {
        guard let digit = highlightedDigit else { return false }
        if board[cell] == digit { return true }
        return board[cell] == 0 && pencil[cell.index] & Candidates.bit(digit) != 0
    }

    func notes(at cell: CellRef) -> UInt16 { pencil[cell.index] }

    /// Units that are full but wrong, for a warning style distinct from the
    /// completion celebration.
    var incorrectUnits: Set<UnitRef> {
        var result = Set<UnitRef>()
        for unitIndex in 0..<Units.count {
            let cells = Units.cells(inUnit: unitIndex)
            guard cells.allSatisfy({ board[$0] != 0 }) else { continue }
            if Set(cells.map { board[$0] }).count != SudokuKit.Grid.size {
                result.insert(UnitRef(unitIndex: unitIndex))
            }
        }
        return result
    }

    var isSolved: Bool {
        Validator.isSolved(board)
    }

    // MARK: - Change handling

    private func boardDidChange() {
        version += 1
        detectNewlyCompletedUnits()

        if isSolved, finishedAt == nil {
            finishedAt = Date()
            isPaused = true
        }
    }

    /// Fires the celebration only for units that became complete *just now*.
    ///
    /// The first computation records the baseline and celebrates nothing, so
    /// loading a saved game does not set off a fanfare for work done yesterday
    /// (`useGameBoard.ts:87`).
    private func detectNewlyCompletedUnits() {
        var complete = Set<UnitRef>()
        for unitIndex in 0..<Units.count {
            let cells = Units.cells(inUnit: unitIndex)
            guard cells.allSatisfy({ board[$0] != 0 }) else { continue }
            guard Set(cells.map { board[$0] }).count == SudokuKit.Grid.size else { continue }
            complete.insert(UnitRef(unitIndex: unitIndex))
        }

        defer { completedUnits = complete }
        guard let previous = completedUnits else { return }
        celebratingUnits = complete.subtracting(previous)
    }

    /// Ends the celebration. Called by the view once its animation has run.
    func clearCelebration() {
        celebratingUnits = []
    }
}
