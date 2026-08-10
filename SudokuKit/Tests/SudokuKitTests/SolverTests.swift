import Testing

@testable import SudokuKit

/// Ports the solver table from `backend/internal/generator/generator_test.go`.
@Suite("Solver")
struct SolverTests {

    @Test("a valid puzzle solves to a complete grid preserving its givens")
    func solvesValidPuzzle() {
        for entry in Fixtures.corpus(kind: "generated-medium") {
            guard let solved = Solver.solve(entry.grid) else {
                Issue.record("failed to solve \(entry.puzzle)")
                continue
            }
            #expect(Validator.isSolved(solved))
            for index in 0..<Grid.cellCount where entry.grid[index] != 0 {
                #expect(solved[index] == entry.grid[index], "solver overwrote a given in \(entry.puzzle)")
            }
        }
    }

    /// Go: `TestSolve_EmptyGrid`. An empty grid is legal, so it solves — to one
    /// of many valid grids.
    @Test("an empty grid solves")
    func solvesEmptyGrid() {
        let solved = Solver.solve(Grid())
        #expect(solved != nil)
        if let solved { #expect(Validator.isSolved(solved)) }
    }

    /// Go: `TestSolve_Unsolvable`.
    @Test("a contradictory grid does not solve")
    func rejectsContradictoryGrid() {
        #expect(Solver.solve(Fixtures.single(kind: "contradiction-row").grid) == nil)
        #expect(Solver.solve(Fixtures.single(kind: "contradiction-box").grid) == nil)
        #expect(Solver.solve(Fixtures.single(kind: "wrong-entry").grid) == nil)
    }

    @Test("solving is deterministic: candidates are tried ascending")
    func solvingIsDeterministic() {
        let grid = Fixtures.corpus(kind: "generated-hard")[0].grid
        let first = Solver.solve(grid)
        for _ in 0..<5 {
            #expect(Solver.solve(grid) == first, "solve is not deterministic")
        }
    }

    @Test("every generated puzzle has exactly one solution")
    func generatedPuzzlesAreUnique() {
        for kind in ["generated-easy", "generated-medium", "generated-hard", "minimal-carve"] {
            for entry in Fixtures.corpus(kind: kind) {
                #expect(Solver.hasUniqueSolution(entry.grid), "\(kind) puzzle is not unique: \(entry.puzzle)")
            }
        }
    }

    @Test("an empty grid has many solutions")
    func emptyGridIsNotUnique() {
        #expect(Solver.countSolutions(Grid(), limit: 2) == 2)
        #expect(!Solver.hasUniqueSolution(Grid()))
    }

    @Test("a contradictory grid has no solutions")
    func contradictionHasNoSolutions() {
        #expect(Solver.countSolutions(Fixtures.single(kind: "contradiction-box").grid, limit: 2) == 0)
    }

    @Test("the limit caps the count", arguments: [0, 1, 2])
    func limitCapsTheCount(limit: Int) {
        #expect(Solver.countSolutions(Grid(), limit: limit) == limit)
    }

    /// The solution the solver finds must be *the* solution when one is unique.
    @Test("a unique puzzle solves to the same grid the counter proved unique")
    func uniqueSolutionIsStable() {
        for entry in Fixtures.corpus where entry.solutions == 1 {
            guard let solved = Solver.solve(entry.grid) else {
                Issue.record("unique puzzle failed to solve: \(entry.puzzle)")
                continue
            }
            #expect(Validator.isSolved(solved))
        }
    }
}
