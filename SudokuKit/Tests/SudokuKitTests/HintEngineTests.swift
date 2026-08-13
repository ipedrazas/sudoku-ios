import Testing

@testable import SudokuKit

@Suite("Hint engine")
struct HintEngineTests {

    private func generated(_ difficulty: Difficulty, seed: UInt64 = 1) -> GeneratedPuzzle {
        var rng = SeededRandom(seed: seed)
        return Generator.generate(difficulty, using: &rng)
    }

    // MARK: - Mistakes

    /// Mistake detection is exact because the solution is always on hand. It has
    /// to run *before* any technique hint: `Rater.rate` reports the easiest tier
    /// for any full grid without inspecting it, so a hint computed from a
    /// corrupted board is reasoning from a false premise.
    @Test("a wrong entry is found exactly")
    func detectsMistake() {
        let puzzle = generated(.medium)
        var board = puzzle.puzzle

        guard let empty = board.emptyCells.first else { return }
        let correct = puzzle.solution[empty]
        let wrong = correct == 1 ? 2 : 1
        board[empty] = wrong

        let hint = HintEngine.hint(for: board, solution: puzzle.solution)
        guard case .mistake(let cell, let expected, let found) = hint.outcome else {
            Issue.record("expected a mistake, got \(hint.outcome)")
            return
        }
        #expect(cell == empty)
        #expect(expected == correct)
        #expect(found == wrong)
    }

    @Test("the earliest mistake is reported, not an arbitrary one")
    func reportsFirstMistake() {
        let puzzle = generated(.medium)
        var board = puzzle.puzzle

        let empties = board.emptyCells
        guard empties.count >= 2 else { return }
        for cell in [empties[0], empties[1]] {
            board[cell] = puzzle.solution[cell] == 1 ? 2 : 1
        }

        guard case .mistake(let cell, _, _) = HintEngine.hint(for: board, solution: puzzle.solution).outcome else {
            Issue.record("expected a mistake")
            return
        }
        #expect(cell == empties[0], "should report the mistake earliest in reading order")
    }

    @Test("a correct partial board is not a mistake")
    func correctProgressIsNotAMistake() {
        let puzzle = generated(.medium)
        var board = puzzle.puzzle
        for cell in board.emptyCells.prefix(10) {
            board[cell] = puzzle.solution[cell]
        }

        #expect(HintEngine.firstMistake(in: board, against: puzzle.solution) == nil)
        if case .mistake = HintEngine.hint(for: board, solution: puzzle.solution).outcome {
            Issue.record("a correct board should never report a mistake")
        }
    }

    @Test("a mistake hint points at the offending cell and its units")
    func mistakeHighlights() {
        let puzzle = generated(.medium)
        var board = puzzle.puzzle
        guard let empty = board.emptyCells.first else { return }
        board[empty] = puzzle.solution[empty] == 1 ? 2 : 1

        let hint = HintEngine.hint(for: board, solution: puzzle.solution)
        #expect(hint.cells == [empty])
        #expect(hint.units.count == 3, "row, column and box")
    }

    // MARK: - Steps

    @Test("a fresh puzzle yields a technique step", arguments: Difficulty.allCases)
    func freshPuzzleYieldsStep(difficulty: Difficulty) {
        let puzzle = generated(difficulty, seed: 7)
        let hint = HintEngine.hint(for: puzzle.puzzle, solution: puzzle.solution)

        guard case .step(let step) = hint.outcome else {
            Issue.record("expected a step for \(difficulty), got \(hint.outcome)")
            return
        }
        #expect(step.tier <= .advanced)
        #expect(!hint.cells.isEmpty || !hint.units.isEmpty, "a hint must point somewhere")
    }

    @Test("a revealed placement is always the solution's digit")
    func revealsCorrectDigit() {
        for seed in UInt64(0)..<10 {
            let puzzle = generated(.easy, seed: seed)
            let hint = HintEngine.hint(for: puzzle.puzzle, solution: puzzle.solution)
            guard let placement = hint.placement else { continue }
            #expect(
                placement.digit == puzzle.solution[placement.cell],
                "hint would place a wrong digit at \(placement.cell)"
            )
        }
    }

    /// Following hints must finish the puzzle. This is the player-facing form of
    /// the promise that generated puzzles never need guessing.
    @Test("following hints solves an easy puzzle")
    func hintsSolveAPuzzle() {
        let puzzle = generated(.easy, seed: 3)
        var board = puzzle.puzzle
        var steps = 0

        while !board.isFull, steps < Grid.cellCount * 2 {
            let hint = HintEngine.hint(for: board, solution: puzzle.solution)
            guard let placement = hint.placement, placement.digit != 0 else { break }
            board[placement.cell] = placement.digit
            steps += 1
        }

        #expect(board == puzzle.solution, "hints did not finish the puzzle after \(steps) steps")
    }

    @Test("a solved board reports solved")
    func solvedBoard() {
        let puzzle = generated(.easy)
        let hint = HintEngine.hint(for: puzzle.solution, solution: puzzle.solution)
        #expect(hint.outcome == .solved)
    }

    // MARK: - Asking for a different hint

    /// The defect three players reported: every elimination technique leaves
    /// `placement` nil, so the hint they could not follow was also the hint they
    /// could not act on. `answer` is what makes every hint actionable, and this
    /// asserts it for the outcomes that used to have nothing.
    @Test("every hint on an unsolved board offers a cell it can fill in")
    func everyHintCanBeActedOn() {
        for difficulty in Difficulty.allCases {
            for seed in UInt64(40)..<48 {
                let puzzle = generated(difficulty, seed: seed)
                var board = puzzle.puzzle
                var seen: Set<CellRef> = []

                // Walk the alternatives too: the dead end appeared after a
                // couple of "show me another", not on the first hint.
                for _ in 0..<4 {
                    let hint = HintEngine.hint(for: board, solution: puzzle.solution, skipping: seen)
                    guard hint.outcome != .solved else { break }

                    guard let answer = hint.answer else {
                        Issue.record("\(difficulty) seed \(seed): \(hint.outcome) offers no way forward")
                        break
                    }
                    #expect(
                        board[answer.cell] == 0 || answer.digit == puzzle.solution[answer.cell],
                        "an offered answer must be the solution's digit"
                    )
                    #expect(answer.digit == puzzle.solution[answer.cell])

                    seen.formUnion(hint.cells)
                    _ = board
                }
            }
        }
    }

    @Test("asking again gives a different hint")
    func alternativesDiffer() {
        for seed in UInt64(60)..<70 {
            let puzzle = generated(.easy, seed: seed)
            let first = HintEngine.hint(for: puzzle.puzzle, solution: puzzle.solution)
            guard case .step = first.outcome else { continue }

            let second = HintEngine.hint(
                for: puzzle.puzzle,
                solution: puzzle.solution,
                skipping: Set(first.cells)
            )
            #expect(second != first, "seed \(seed): the second ask repeated the first hint")
            #expect(
                !second.cells.contains(where: Set(first.cells).contains),
                "seed \(seed): the alternative points at a cell already shown"
            )
        }
    }

    /// The alternatives are singles because a player who could not follow an
    /// X-wing is not helped by a second X-wing. Every one of them also has to be
    /// *true of the board in front of them* — which is why they are computed
    /// from a candidate snapshot rather than from the solver, whose later steps
    /// are only valid once its earlier ones have been applied.
    @Test("every offered alternative is a valid deduction on the player's board")
    func alternativesAreValid() {
        for difficulty in Difficulty.allCases {
            for seed in UInt64(80)..<88 {
                let puzzle = generated(difficulty, seed: seed)
                let board = puzzle.puzzle

                for step in HintEngine.followableSingles(in: board) {
                    guard let placed = step.placedCell else {
                        Issue.record("a followable single must place a digit")
                        continue
                    }
                    #expect(board[placed.cell] == 0, "\(placed.cell) is not empty")
                    #expect(
                        placed.digit == puzzle.solution[placed.cell],
                        """
                        \(difficulty) seed \(seed): \(placed.cell) claimed \(placed.digit), \
                        solution says \(puzzle.solution[placed.cell])
                        """
                    )
                }
            }
        }
    }

    @Test("running out of explanations still hands over a cell")
    func exhaustedHintsStillOfferSomething() {
        let puzzle = generated(.medium, seed: 5)
        let board = puzzle.puzzle
        // Everything is off the table, which is where repeated asking ends up.
        let seen = Set(board.emptyCells)

        let hint = HintEngine.hint(for: board, solution: puzzle.solution, skipping: seen)
        guard case .allShown(let cell, let digit) = hint.outcome else {
            Issue.record("expected allShown, got \(hint.outcome)")
            return
        }
        #expect(digit == puzzle.solution[cell])
        #expect(hint.placement?.cell == cell)
        for level in HintLevel.allCases {
            #expect(!hint.text(at: level).isEmpty)
        }
    }

    /// `skipping` defaults to empty and that path must stay bit-for-bit what it
    /// was: the rater's order is the definition of difficulty, and the first
    /// hint a player gets is the rater's answer.
    @Test("the default hint is unchanged by the alternatives path")
    func defaultHintIsUntouched() {
        for difficulty in Difficulty.allCases {
            for seed in UInt64(90)..<96 {
                let puzzle = generated(difficulty, seed: seed)
                let hint = HintEngine.hint(for: puzzle.puzzle, solution: puzzle.solution)
                guard case .step(let step) = hint.outcome else { continue }
                #expect(step == Rater.nextStep(for: puzzle.puzzle))
            }
        }
    }

    // MARK: - Copy

    @Test("every level produces non-empty text for every outcome")
    func textIsAlwaysPresent() {
        var boards: [Grid] = []

        let puzzle = generated(.expert, seed: 11)
        boards.append(puzzle.puzzle)
        boards.append(puzzle.solution)

        var mistaken = puzzle.puzzle
        if let empty = mistaken.emptyCells.first {
            mistaken[empty] = puzzle.solution[empty] == 1 ? 2 : 1
        }
        boards.append(mistaken)

        for board in boards {
            let hint = HintEngine.hint(for: board, solution: puzzle.solution)
            for level in HintLevel.allCases {
                #expect(!hint.text(at: level).isEmpty, "empty copy for \(hint.outcome) at \(level)")
            }
        }
    }

    /// The first three levels teach; only `.reveal` gives the answer away. A
    /// nudge that leaks the digit defeats the point of escalating at all.
    @Test("levels below reveal do not name the answer")
    func lowerLevelsWithholdTheAnswer() {
        for seed in UInt64(0)..<8 {
            let puzzle = generated(.easy, seed: seed)
            let hint = HintEngine.hint(for: puzzle.puzzle, solution: puzzle.solution)
            guard case .step(let step) = hint.outcome, let placement = step.placedCell else { continue }

            let nudge = hint.text(at: .nudge)
            #expect(
                !nudge.contains(placement.cell.description),
                "a nudge should not name the cell: \(nudge)"
            )
            #expect(
                hint.text(at: .reveal).contains(placement.cell.description),
                "a reveal should name the cell"
            )
        }
    }

    @Test("hint costs escalate")
    func costsEscalate() {
        #expect(HintLevel.nudge.cost <= HintLevel.explain.cost)
        #expect(HintLevel.explain.cost < HintLevel.reveal.cost)
        #expect(HintLevel.allCases.count == 4)
    }

    @Test("technique names read as a player would say them")
    func techniqueNames() {
        let cells = [CellRef(index: 0), CellRef(index: 1)]
        #expect(TechniqueStep.nakedSingle(cell: cells[0], digit: 1).techniqueName == "naked single")
        #expect(
            TechniqueStep.nakedSubset(cells: cells, digits: [1, 2], unit: .row(0), eliminates: [])
                .techniqueName == "naked pair"
        )
        #expect(
            TechniqueStep.nakedSubset(
                cells: cells + [CellRef(index: 2)], digits: [1, 2, 3], unit: .row(0), eliminates: []
            ).techniqueName == "naked triple"
        )
        #expect(TechniqueStep.xWing(digit: 4, lines: [.row(0), .row(1)], eliminates: []).techniqueName == "X-wing")
    }

    @Test("step tiers map to the rater's tiers")
    func stepTiers() {
        let cell = CellRef(index: 0)
        #expect(TechniqueStep.nakedSingle(cell: cell, digit: 1).tier == .nakedSingle)
        #expect(TechniqueStep.hiddenSingle(cell: cell, digit: 1, unit: .row(0)).tier == .hiddenSingle)
        #expect(TechniqueStep.lockedCandidate(digit: 1, box: 0, line: .row(0), eliminates: []).tier == .locked)
        #expect(TechniqueStep.xWing(digit: 1, lines: [], eliminates: []).tier == .advanced)
    }
}
