import Testing

@testable import SudokuKit

@Suite("Auto notes and notes-aware hints")
struct AutoNotesTests {

    private func generated(_ difficulty: Difficulty, seed: UInt64) -> GeneratedPuzzle {
        var rng = SeededRandom(seed: seed)
        return Generator.generate(difficulty, using: &rng)
    }

    private struct Position {
        let puzzle: GeneratedPuzzle
        let board: Grid
        let step: TechniqueStep
    }

    /// Plays singles from the solution until the engine's next step is an
    /// elimination, so a test has a position where one is on offer.
    private func positionWithElimination(_ difficulty: Difficulty = .hard) -> Position? {
        for seed in UInt64(1)...40 {
            let puzzle = generated(difficulty, seed: seed)
            var board = puzzle.puzzle
            while let step = Rater.nextStep(for: board) {
                guard let placed = step.placedCell else { return Position(puzzle: puzzle, board: board, step: step) }
                board[placed.cell] = placed.digit
            }
        }
        return nil
    }

    private func notes(_ grid: CandidateGrid) -> [UInt16] {
        (0..<Grid.cellCount).map { grid[$0] }
    }

    /// What an elimination step removes, as (cell, digit-mask) pairs.
    private func removals(of step: TechniqueStep) -> [(CellRef, UInt16)] {
        switch step {
        case .lockedCandidate(let digit, _, _, let cells), .xWing(let digit, _, let cells):
            cells.map { ($0, Candidates.bit(digit)) }
        case .nakedSubset(_, let digits, _, let cells):
            cells.map { ($0, Candidates.mask(of: digits)) }
        case .hiddenSubset(let cells, let digits, _):
            cells.map { ($0, ~Candidates.mask(of: digits)) }
        case .nakedSingle, .hiddenSingle:
            []
        }
    }

    // MARK: - Fill

    @Test("filling never crosses out the right answer", arguments: Difficulty.allCases)
    func fillKeepsSolution(difficulty: Difficulty) {
        for seed in UInt64(1)...5 {
            let puzzle = generated(difficulty, seed: seed)
            var board = puzzle.puzzle
            // Fresh, and again halfway through.
            for _ in 0..<2 {
                let filled = AutoNotes.fill(board: board, notes: [], solution: puzzle.solution)
                let plain = CandidateGrid(board)
                for index in 0..<Grid.cellCount {
                    guard board[index] == 0 else {
                        #expect(filled[index] == 0)
                        continue
                    }
                    #expect(filled[index] & Candidates.bit(puzzle.solution[index]) != 0)
                    #expect(filled[index] & ~plain[index] == 0, "fill must never add a digit the board rules out")
                }
                for cell in board.emptyCells.prefix(board.emptyCells.count / 2) {
                    board[cell] = puzzle.solution[cell]
                }
            }
        }
    }

    @Test("filling applies the eliminations the engine can see")
    func fillAppliesLogic() throws {
        let position = try #require(positionWithElimination())
        let (puzzle, board, step) = (position.puzzle, position.board, position.step)
        let filled = AutoNotes.fill(board: board, notes: [], solution: puzzle.solution)
        for (cell, mask) in removals(of: step) {
            #expect(filled[cell.index] & mask == 0, "\(step) should already be applied to \(cell)")
        }
    }

    @Test("filling keeps the player's own eliminations")
    func fillKeepsPlayerEliminations() throws {
        let puzzle = generated(.medium, seed: 3)
        let board = puzzle.puzzle
        let plain = CandidateGrid(board)
        let cell = try #require(board.emptyCells.first { Candidates.count(plain[$0]) >= 3 })
        let solution = Candidates.bit(puzzle.solution[cell])
        // Keep the answer and one other digit; cross out the rest.
        let other = Candidates.lowest(plain[cell] & ~solution)
        var mine = [UInt16](repeating: 0, count: Grid.cellCount)
        mine[cell.index] = solution | Candidates.bit(other)

        let filled = AutoNotes.fill(board: board, notes: mine, solution: puzzle.solution)
        #expect(filled[cell.index] & ~mine[cell.index] == 0, "a crossed-out digit came back")
        #expect(filled[cell.index] & solution != 0)
    }

    @Test("notes that lost the answer are kept but not reasoned from")
    func fillDoesNotReasonFromWrongNotes() throws {
        let puzzle = generated(.medium, seed: 4)
        let board = puzzle.puzzle
        let plain = CandidateGrid(board)
        let cell = try #require(board.emptyCells.first { Candidates.count(plain[$0]) >= 2 })
        var wrong = [UInt16](repeating: 0, count: Grid.cellCount)
        wrong[cell.index] = plain[cell] & ~Candidates.bit(puzzle.solution[cell])

        let filled = AutoNotes.fill(board: board, notes: wrong, solution: puzzle.solution)
        let clean = AutoNotes.fill(board: board, notes: [], solution: puzzle.solution)
        for index in 0..<Grid.cellCount where index != cell.index {
            #expect(filled[index] == clean[index], "a wrong note in \(cell) changed \(CellRef(index: index))")
        }
        #expect(filled[cell.index] != 0)
    }

    @Test("a board with a wrong digit is only cleaned, not deduced from")
    func fillSkipsLogicOnMistake() throws {
        let position = try #require(positionWithElimination())
        let (puzzle, board) = (position.puzzle, position.board)
        var wrong = board
        let cell = try #require(board.emptyCells.first)
        let plain = CandidateGrid(board)
        let bad = Candidates.lowest(plain[cell] & ~Candidates.bit(puzzle.solution[cell]))
        try #require(bad != 0)
        wrong[cell] = bad

        let filled = AutoNotes.fill(board: wrong, notes: [], solution: puzzle.solution)
        #expect(filled == notes(CandidateGrid(wrong)))
    }

    // MARK: - Hints

    @Test("a hint the player's notes already show is not given again")
    func hintSkipsKnownElimination() throws {
        let position = try #require(positionWithElimination())
        let (puzzle, board, step) = (position.puzzle, position.board, position.step)
        #expect(HintEngine.hint(for: board, solution: puzzle.solution).outcome == .step(step))

        var known = notes(CandidateGrid(board))
        for (cell, mask) in removals(of: step) { known[cell.index] &= ~mask }

        let hint = HintEngine.hint(for: board, solution: puzzle.solution, notes: known)
        #expect(hint.outcome != .step(step), "the notes already show \(step)")
    }

    @Test("notes that crossed out the answer do not change the hint")
    func hintIgnoresWrongNotes() throws {
        let position = try #require(positionWithElimination())
        let (puzzle, board, step) = (position.puzzle, position.board, position.step)
        let plain = CandidateGrid(board)
        let wrong = (0..<Grid.cellCount).map { plain[$0] & ~Candidates.bit(puzzle.solution[$0]) }

        let hint = HintEngine.hint(for: board, solution: puzzle.solution, notes: wrong)
        #expect(hint.outcome == .step(step))
    }

    @Test("no notes means the hint is exactly what it always was")
    func hintWithoutNotesUnchanged() {
        for seed in UInt64(1)...10 {
            let puzzle = generated(.hard, seed: seed)
            let blank = [UInt16](repeating: 0, count: Grid.cellCount)
            #expect(
                HintEngine.hint(for: puzzle.puzzle, solution: puzzle.solution, notes: blank)
                    == HintEngine.hint(for: puzzle.puzzle, solution: puzzle.solution)
            )
        }
    }

    @Test("a single that only the notes make single says so")
    func singleFromNotesIsWordedForNotes() throws {
        for seed in UInt64(1)...20 {
            let puzzle = generated(.hard, seed: seed)
            let board = puzzle.puzzle
            let plain = CandidateGrid(board)
            guard let cell = board.emptyCells.first, Candidates.count(plain[cell]) > 1 else { continue }
            var mine = [UInt16](repeating: 0, count: Grid.cellCount)
            mine[cell.index] = Candidates.bit(puzzle.solution[cell])

            let hint = HintEngine.hint(for: board, solution: puzzle.solution, notes: mine)
            #expect(hint.outcome == .step(.nakedSingle(cell: cell, digit: puzzle.solution[cell])))
            #expect(hint.reliesOnNotes)
            #expect(hint.text(at: .explain) == Copy.text("hint.nakedSingle.explainNotes", cell.description))
            return
        }
        Issue.record("no seed produced a first empty cell with more than one candidate")
    }
}
