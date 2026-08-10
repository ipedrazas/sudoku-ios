import Testing

@testable import SudokuKit

/// Ports the table from `backend/internal/validator/validator_test.go`.
@Suite("Validator")
struct ValidatorTests {

    @Test("an empty grid is valid but not complete")
    func emptyGrid() {
        let result = Validator.validate(Grid())
        #expect(result.isValid)
        #expect(!result.isComplete)
    }

    @Test("a solved grid is valid and complete")
    func solvedGrid() {
        let grid = Fixtures.single(kind: "solved-grid").grid
        let result = Validator.validate(grid)
        #expect(result.isValid)
        #expect(result.isComplete)
        #expect(Validator.isSolved(grid))
    }

    @Test("a partially filled legal grid is valid but not complete")
    func partialGrid() {
        var grid = Grid()
        grid[0, 0] = 1
        grid[1, 1] = 2
        grid[8, 8] = 9

        let result = Validator.validate(grid)
        #expect(result.isValid)
        #expect(!result.isComplete)
    }

    @Test("a duplicate in a row is invalid")
    func duplicateRow() {
        var grid = Grid()
        grid[0, 0] = 5
        grid[0, 4] = 5
        #expect(!Validator.obeysRules(grid))
    }

    @Test("a duplicate in a column is invalid")
    func duplicateColumn() {
        var grid = Grid()
        grid[0, 3] = 7
        grid[6, 3] = 7
        #expect(!Validator.obeysRules(grid))
    }

    @Test("a duplicate in a box is invalid")
    func duplicateBox() {
        var grid = Grid()
        grid[0, 0] = 5
        grid[1, 1] = 5
        #expect(!Validator.obeysRules(grid))
    }

    /// Go: `validator.go:33-36`. A full grid that breaks the rules is not
    /// "complete", it is wrong — which is what makes `isSolved` safe to use for
    /// win detection.
    @Test("a full but illegal grid is neither valid nor complete")
    func fullButIllegal() {
        let grid = Fixtures.single(kind: "wrong-entry").grid
        let result = Validator.validate(grid)

        #expect(grid.isFull)
        #expect(!result.isValid)
        #expect(!result.isComplete)
        #expect(!Validator.isSolved(grid))
    }

    @Test("conflicts report both halves of a duplicate pair")
    func conflictsReportBothCells() {
        var grid = Grid()
        grid[0, 0] = 5
        grid[0, 4] = 5

        let conflicts = Validator.conflicts(in: grid)
        #expect(conflicts == [CellRef(row: 0, col: 0), CellRef(row: 0, col: 4)])
    }

    @Test("a cell conflicting in two units is reported once")
    func conflictsDeduplicate() {
        var grid = Grid()
        grid[0, 0] = 5
        grid[0, 4] = 5  // same row
        grid[4, 0] = 5  // same column

        let conflicts = Validator.conflicts(in: grid)
        #expect(conflicts.count == 3)
        #expect(conflicts.contains(CellRef(row: 0, col: 0)))
    }

    @Test("a legal grid has no conflicts")
    func noConflictsWhenLegal() {
        for entry in Fixtures.corpus where entry.solutions >= 1 {
            #expect(Validator.conflicts(in: entry.grid).isEmpty, "unexpected conflict in \(entry.puzzle)")
        }
    }

    @Test("conflicts and obeysRules always agree")
    func conflictsAgreeWithRules() {
        for entry in Fixtures.corpus {
            let hasConflicts = !Validator.conflicts(in: entry.grid).isEmpty
            #expect(hasConflicts == !Validator.obeysRules(entry.grid), "disagreement on \(entry.puzzle)")
        }
    }
}
