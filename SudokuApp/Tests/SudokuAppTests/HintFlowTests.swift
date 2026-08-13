import SudokuKit
import Testing

@testable import SudokuApp

/// The hint flow, which is the part of the app players wrote in about.
///
/// Three of them described the same thing: a hint they could not follow, and no
/// way past it. The engine only ever offered its single best deduction, and the
/// sheet only offered a button when that deduction happened to place a digit —
/// which every elimination technique does not. These tests hold both halves of
/// the fix: asking again gives something different, and every hint can be cashed
/// in for a filled-in cell.
@Suite("Hints")
@MainActor
struct HintFlowTests {

    private func session(
        _ difficulty: Difficulty = .easy,
        seed: UInt64 = 1
    ) -> GameSession {
        var rng = SeededRandom(seed: seed)
        return GameSession(puzzle: Generator.generate(difficulty, using: &rng), showsConflicts: true)
    }

    private func firstEmptyCell(_ session: GameSession) -> CellRef {
        session.board.emptyCells[0]
    }

    @Test("hints charge only the difference when a player escalates")
    func hintCosts() {
        let session = session()

        session.hint(at: .nudge)
        let afterNudge = session.hintPoints
        #expect(afterNudge == HintLevel.nudge.cost)

        session.hint(at: .reveal, previousLevel: .nudge)
        #expect(
            session.hintPoints == HintLevel.reveal.cost,
            "escalating should cost the same as asking for the answer outright"
        )
        #expect(session.hintsUsed == 1)
    }

    @Test("applying a hint fills the right digit and is undoable")
    func applyingHints() {
        let session = session()
        let hint = session.hint(at: .reveal)
        session.applyHint(hint)

        guard let placement = hint.placement else { return }
        #expect(session.board[placement.cell] == session.puzzle.solution[placement.cell])
        #expect(session.canUndo, "a hint is a move like any other")
    }

    /// The reported defect, at the level a player meets it: ask for a hint, fail
    /// to follow it, ask for another, and keep getting the same one.
    @Test("asking for a different hint gives a different hint")
    func differentHints() {
        let session = session(.expert, seed: 3)
        var hint = session.hint(at: .nudge)
        var seen: [Hint] = [hint]

        for _ in 0..<3 {
            hint = session.differentHint(from: hint)
            #expect(!seen.contains(hint), "the engine repeated a hint it had already given")
            seen.append(hint)
        }
    }

    @Test("a different hint is free")
    func differentHintsAreFree() {
        let session = session()
        let first = session.hint(at: .nudge)
        let charged = session.hintPoints

        _ = session.differentHint(from: first)
        #expect(
            session.hintPoints == charged,
            "a player who could not use the first hint should not pay twice for the second"
        )
    }

    /// Every elimination technique leaves `placement` nil, which is how a player
    /// used to reach the last level of a hint with nothing to press. Whatever
    /// the outcome, `revealAnswer` has to move the board.
    @Test("a hint can always be turned into a filled-in cell", arguments: Difficulty.allCases)
    func everyHintCanBeCashedIn(difficulty: Difficulty) {
        let session = session(difficulty, seed: 7)
        var hint = session.hint(at: .nudge)

        // Walk to a hint the old sheet could not act on, if this puzzle has one.
        for _ in 0..<4 where hint.placement == nil {
            hint = session.differentHint(from: hint)
        }

        let before = session.board
        session.revealAnswer(hint, from: .nudge)
        #expect(session.board != before, "revealing an answer must fill something in")
        #expect(session.board == session.puzzle.solution || session.board.emptyCells.count < before.emptyCells.count)
        #expect(session.canUndo, "a revealed cell is a move like any other")
    }

    @Test("cashing in an answer costs exactly what a reveal costs")
    func answersCostAReveal() {
        let session = session()
        let hint = session.hint(at: .nudge)
        session.revealAnswer(hint, from: .nudge)

        #expect(session.hintPoints == HintLevel.reveal.cost)
        #expect(session.hintsUsed == 1)
    }

    @Test("a move clears what the player has already been shown")
    func movesResetTheHintHistory() {
        let session = session()
        let hint = session.hint(at: .nudge)
        _ = session.differentHint(from: hint)
        #expect(!session.hintsShown.isEmpty)

        let cell = firstEmptyCell(session)
        session.select(cell)
        session.input(session.puzzle.solution[cell])

        #expect(session.hintsShown.isEmpty, "a new position deserves the engine's best hint again")
    }
}
