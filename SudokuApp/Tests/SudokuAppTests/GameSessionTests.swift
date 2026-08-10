import SudokuKit
import Testing

@testable import SudokuApp

/// `GameSession` is tested headlessly — no view rendering, no simulator beyond
/// the one hosting the bundle. The behaviours below are the ones the web app
/// gets right and that are easy to lose in a port.
@Suite("GameSession")
@MainActor
struct GameSessionTests {

    private func session(_ difficulty: Difficulty = .easy, seed: UInt64 = 1) -> GameSession {
        var rng = SeededRandom(seed: seed)
        return GameSession(puzzle: Generator.generate(difficulty, using: &rng))
    }

    private func firstEmptyCell(_ session: GameSession) -> CellRef? {
        session.board.emptyCells.first
    }

    @Test("a new session starts from the puzzle as dealt")
    func startsFromPuzzle() {
        let session = session()
        #expect(session.board == session.puzzle.puzzle)
        #expect(session.selection == nil)
        #expect(!session.isSolved)
    }

    @Test("givens are marked, entries are not")
    func givenMask() {
        let session = session()
        for index in 0..<SudokuKit.Grid.cellCount {
            let cell = CellRef(index: index)
            #expect(session.isGiven(cell) == (session.puzzle.puzzle[index] != 0))
        }
    }

    @Test("selecting a cell, then selecting it again, clears the selection")
    func selectionToggles() {
        let session = session()
        let cell = CellRef(index: 0)

        session.select(cell)
        #expect(session.selection == cell)

        session.select(cell)
        #expect(session.selection == nil, "tapping the selected cell should deselect it")
    }

    @Test("a digit lands in the selected cell")
    func inputPlacesDigit() {
        let session = session()
        guard let cell = firstEmptyCell(session) else { return }

        session.select(cell)
        session.input(5)
        #expect(session.board[cell] == 5)
    }

    /// Web parity (`useGameBoard.ts:286-289`): the same key both writes and
    /// undoes, which is what a player expects after a mistype.
    @Test("entering the digit already there erases it")
    func inputTogglesDigit() {
        let session = session()
        guard let cell = firstEmptyCell(session) else { return }

        session.select(cell)
        session.input(5)
        session.input(5)
        #expect(session.board[cell] == 0)
    }

    @Test("givens cannot be overwritten or erased")
    func givensAreImmutable() {
        let session = session()
        guard
            let given = (0..<SudokuKit.Grid.cellCount)
                .map({ CellRef(index: $0) })
                .first(where: { session.isGiven($0) })
        else { return }

        let original = session.board[given]
        session.select(given)
        session.input(original == 1 ? 2 : 1)
        #expect(session.board[given] == original)

        session.erase()
        #expect(session.board[given] == original)
    }

    @Test("input with nothing selected does nothing")
    func inputWithoutSelection() {
        let session = session()
        let before = session.board
        session.input(7)
        session.erase()
        #expect(session.board == before)
    }

    @Test("erase clears the selected cell")
    func erase() {
        let session = session()
        guard let cell = firstEmptyCell(session) else { return }

        session.select(cell)
        session.input(4)
        session.erase()
        #expect(session.board[cell] == 0)
    }

    @Test("restart returns to the dealt puzzle")
    func restart() {
        let session = session()
        guard let cell = firstEmptyCell(session) else { return }

        session.select(cell)
        session.input(9)
        session.restart()

        #expect(session.board == session.puzzle.puzzle)
        #expect(session.selection == nil)
    }

    @Test("a duplicate is reported as a conflict")
    func conflicts() {
        let session = session()
        #expect(session.conflicts.isEmpty, "a fresh puzzle has no conflicts")

        // Copy a given into an empty cell in the same row.
        guard
            let given = (0..<SudokuKit.Grid.size)
                .map({ CellRef(row: 0, col: $0) })
                .first(where: { session.isGiven($0) }),
            let target = (0..<SudokuKit.Grid.size)
                .map({ CellRef(row: 0, col: $0) })
                .first(where: { session.board[$0] == 0 })
        else { return }

        session.select(target)
        session.input(session.board[given])

        #expect(session.conflicts.contains(target))
        #expect(session.conflicts.contains(given), "both halves of a duplicate pair are reported")
    }

    @Test("remaining counts track what is left to place")
    func remainingCounts() {
        let session = session()
        guard let cell = firstEmptyCell(session) else { return }

        let digit = session.puzzle.solution[cell]
        let before = session.remainingCounts[digit] ?? 0

        session.select(cell)
        session.input(digit)
        #expect(session.remainingCounts[digit] == before - 1)

        // Across the whole board, every digit is placed exactly nine times.
        session.restart()
        for index in 0..<SudokuKit.Grid.cellCount where session.board[index] == 0 {
            let cell = CellRef(index: index)
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
        #expect(session.remainingCounts.values.allSatisfy { $0 == 0 })
    }

    @Test("filling the board correctly registers a solve")
    func solving() {
        let session = session()
        for index in 0..<SudokuKit.Grid.cellCount where session.board[index] == 0 {
            let cell = CellRef(index: index)
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }

        #expect(session.isSolved)
        #expect(session.board == session.puzzle.solution)
        #expect(session.conflicts.isEmpty)
    }

    @Test("a full but wrong board is not a solve")
    func fullButWrongIsNotSolved() {
        let session = session()
        var wrongCell: CellRef?

        for index in 0..<SudokuKit.Grid.cellCount where session.board[index] == 0 {
            let cell = CellRef(index: index)
            session.select(cell)
            let correct = session.puzzle.solution[cell]
            if wrongCell == nil {
                session.input(correct == 1 ? 2 : 1)
                wrongCell = cell
            } else {
                session.input(correct)
            }
        }

        #expect(session.board.isFull)
        #expect(!session.isSolved, "a filled board that breaks the rules is wrong, not finished")
    }
}
