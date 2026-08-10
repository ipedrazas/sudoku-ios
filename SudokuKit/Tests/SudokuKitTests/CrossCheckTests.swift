import Testing

@testable import SudokuKit

/// The proof that the port is correct.
///
/// The technique rater is the most valuable code in the project and the easiest
/// to get subtly wrong: a mis-ported elimination turns an "easy" puzzle into one
/// that needs an X-wing, and nothing in the app would notice. These tests assert
/// the Swift port agrees with the Go implementation on every entry of a 297-case
/// corpus spanning all five tiers.
///
/// **If one of these fails, the Swift change is wrong until proven otherwise.**
/// Regenerating the fixture to make it pass defeats the entire point.
@Suite("Go↔Swift cross-check")
struct CrossCheckTests {

    @Test("the corpus is present and covers every tier")
    func corpusIsUsable() {
        let corpus = Fixtures.corpus
        #expect(corpus.count >= 250, "corpus has shrunk — regenerate with `task fixtures`")

        for tier in Tier.allCases {
            let matching = corpus.filter { $0.tier == tier.rawValue }
            #expect(!matching.isEmpty, "no corpus entry rates \(tier); the rater would be untested there")
        }

        // Without multi-solution and zero-solution cases, uniqueness checking
        // would only ever be exercised on its happy path.
        #expect(corpus.contains { $0.solutions == 0 })
        #expect(corpus.contains { $0.solutions == 1 })
        #expect(corpus.contains { $0.solutions >= 2 })
    }

    @Test("Rater agrees with the Go implementation on every corpus entry")
    func raterMatchesGo() {
        for entry in Fixtures.corpus {
            let actual = Rater.rate(entry.grid)
            #expect(
                actual == entry.expectedTier,
                """
                tier mismatch on a '\(entry.kind)' puzzle (\(entry.clues) clues)
                expected \(entry.expectedTier.rawValue) (Go), got \(actual.rawValue) (Swift)
                \(entry.puzzle)
                \(entry.grid)
                """
            )
        }
    }

    @Test("solution counts agree with an independent Go counter")
    func solutionCountsMatchGo() {
        for entry in Fixtures.corpus {
            let actual = Solver.countSolutions(entry.grid, limit: 2)
            #expect(
                actual == entry.solutions,
                """
                solution-count mismatch on a '\(entry.kind)' puzzle (\(entry.clues) clues)
                expected \(entry.solutions) (Go), got \(actual) (Swift)
                \(entry.puzzle)
                """
            )
        }
    }

    /// Ports `TestRate_AgreesWithSolver` (`difficulty_test.go:37`) and widens it
    /// from five generated puzzles to every solvable entry in the corpus: the
    /// technique solver must never claim a puzzle yields to logic when the
    /// backtracking solver cannot solve it at all.
    ///
    /// Restricted to entries that actually have a solution. The corpus contains
    /// deliberately broken grids, and `rate` reports `.nakedSingle` for any full
    /// grid without inspecting it — see `fullButInvalidGridsRateEasiest`.
    @Test("anything solvable and rated below `beyond` actually solves")
    func ratedPuzzlesAreSolvable() {
        for entry in Fixtures.corpus where entry.expectedTier < .beyond && entry.solutions >= 1 {
            let solved = Solver.solve(entry.grid)
            #expect(
                solved != nil,
                "rated \(entry.expectedTier.rawValue) but the solver could not solve it:\n\(entry.puzzle)"
            )
            if let solved {
                #expect(Validator.isSolved(solved), "solver returned an invalid solution for \(entry.puzzle)")
            }
        }
    }

    /// Stepping the technique solver must never produce an illegal board.
    ///
    /// This is the property behind the app's promise that "hard" never means
    /// "guess": every placement the engine suggests is forced by logic, so
    /// following hints can never paint the player into a corner.
    @Test("stepping through techniques never produces an illegal board")
    func steppingKeepsBoardLegal() {
        for entry in Fixtures.corpus where entry.expectedTier < .beyond && entry.solutions >= 1 {
            var board = entry.grid
            var steps = 0
            while let step = Rater.nextStep(for: board), let placed = step.placedCell, steps < Grid.cellCount {
                board[placed.cell] = placed.digit
                steps += 1
            }
            // Elimination-only steps place nothing, so stepping can stall before
            // the grid fills. What must never happen is a wrong entry.
            #expect(Validator.obeysRules(board), "stepping produced an illegal board from \(entry.puzzle)")
        }
    }

    /// A quirk of the Go implementation, ported faithfully and worth pinning:
    /// `Rate` loops only while empty cells remain, so a *full* grid returns
    /// `.nakedSingle` whether or not it is correct (`difficulty.go:133`).
    ///
    /// The consequence is real: the hint engine must check the player's board
    /// against the stored solution *before* asking for a tier, or a board full
    /// of mistakes would report as the easiest possible puzzle.
    @Test("a full but invalid grid still rates easiest")
    func fullButInvalidGridsRateEasiest() {
        let entry = Fixtures.single(kind: "wrong-entry")
        let grid = entry.grid

        #expect(grid.isFull)
        #expect(!Validator.obeysRules(grid), "the 'wrong-entry' fixture should contain a duplicate")
        #expect(Rater.rate(grid) == .nakedSingle)
        #expect(Solver.solve(grid) == nil)
        #expect(Solver.countSolutions(grid, limit: 2) == 0)
    }
}
