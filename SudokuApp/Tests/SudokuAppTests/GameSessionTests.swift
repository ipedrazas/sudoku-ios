import SudokuKit
import Testing

@testable import SudokuApp

/// `GameSession` is tested headlessly — no view rendering. The behaviours below
/// are the ones the web app gets right and that are easy to lose in a port.
@Suite("GameSession")
@MainActor
struct GameSessionTests {

    private func session(
        _ difficulty: Difficulty = .easy,
        seed: UInt64 = 1,
        showsConflicts: Bool = true
    ) -> GameSession {
        var rng = SeededRandom(seed: seed)
        return GameSession(puzzle: Generator.generate(difficulty, using: &rng), showsConflicts: showsConflicts)
    }

    private func firstEmptyCell(_ session: GameSession) -> CellRef {
        // Every generated puzzle has empty cells; a failure here means the
        // generator is broken, not this test.
        session.board.emptyCells[0]
    }

    private func firstGiven(_ session: GameSession) -> CellRef {
        (0..<SudokuKit.Grid.cellCount).map { CellRef(index: $0) }.first { session.isGiven($0) } ?? CellRef(index: 0)
    }

    private func solve(_ session: GameSession) {
        for index in 0..<SudokuKit.Grid.cellCount where session.board[index] == 0 {
            let cell = CellRef(index: index)
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
    }

    // MARK: - Basics

    @Test("a new session starts from the puzzle as dealt")
    func startsFromPuzzle() {
        let session = session()
        #expect(session.board == session.puzzle.puzzle)
        #expect(session.selection == nil)
        #expect(!session.isSolved)
        #expect(!session.canUndo)
        #expect(!session.canRedo)
        #expect(session.elapsedSeconds == 0)
    }

    @Test("givens are marked, entries are not")
    func givenMask() {
        let session = session()
        for index in 0..<SudokuKit.Grid.cellCount {
            #expect(session.isGiven(CellRef(index: index)) == (session.puzzle.puzzle[index] != 0))
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

    @Test("a digit lands in the selected cell, and repeating it erases")
    func inputTogglesDigit() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.select(cell)
        session.input(5)
        #expect(session.board[cell] == 5)

        session.input(5)
        #expect(session.board[cell] == 0, "the same key should both write and undo")
    }

    @Test("givens cannot be overwritten or erased")
    func givensAreImmutable() {
        let session = session()
        let given = firstGiven(session)
        let original = session.board[given]

        session.select(given)
        session.input(original == 1 ? 2 : 1)
        session.erase()
        #expect(session.board[given] == original)
        #expect(!session.canUndo, "a rejected edit should not enter the history")
    }

    @Test("out-of-range digits are ignored", arguments: [0, 10, -1])
    func rejectsInvalidDigits(digit: Int) {
        let session = session()
        session.select(firstEmptyCell(session))
        session.input(digit)
        #expect(!session.canUndo)
    }

    @Test("restart returns everything to the dealt state")
    func restart() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.select(cell)
        session.input(9)
        session.toggleNotes()
        session.tick(.seconds(30))
        session.restart()

        #expect(session.board == session.puzzle.puzzle)
        #expect(session.selection == nil)
        #expect(!session.canUndo)
        #expect(session.elapsedSeconds == 0)
        #expect(session.pencil.allSatisfy { $0 == 0 })
    }

    // MARK: - Pencil marks

    @Test("notes mode toggles candidates instead of placing digits")
    func pencilMarks() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.toggleNotes()
        session.select(cell)
        session.input(3)
        session.input(7)

        #expect(session.board[cell] == 0, "notes must not fill the cell")
        #expect(Candidates.digits(session.notes(at: cell)) == [3, 7])

        session.input(3)
        #expect(Candidates.digits(session.notes(at: cell)) == [7], "entering a note again removes it")
    }

    @Test("placing a value clears that cell's notes")
    func placingClearsNotes() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.toggleNotes()
        session.select(cell)
        session.input(3)
        session.toggleNotes()
        session.input(5)

        #expect(session.board[cell] == 5)
        #expect(session.notes(at: cell) == 0)
    }

    @Test("notes cannot be added to a filled cell")
    func noNotesOnFilledCells() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.select(cell)
        session.input(5)
        session.toggleNotes()
        session.input(3)

        #expect(session.notes(at: cell) == 0)
        #expect(session.board[cell] == 5)
    }

    @Test("a one-shot note does not disturb notes mode")
    func oneShotNote() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.select(cell)
        session.inputNote(4)

        #expect(!session.isPencilMode, "a long-press note should not flip the mode")
        #expect(Candidates.digits(session.notes(at: cell)) == [4])
    }

    @Test("auto-fill marks every legal candidate")
    func autoFillNotes() {
        let session = session()
        session.autoFillNotes()

        let expected = CandidateGrid(session.board)
        for index in 0..<SudokuKit.Grid.cellCount {
            let cell = CellRef(index: index)
            #expect(session.notes(at: cell) == (session.board[index] == 0 ? expected[index] : 0))
        }
    }

    // MARK: - History

    @Test("undo and redo walk the history")
    func undoRedo() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.select(cell)
        session.input(5)
        #expect(session.canUndo)

        session.undo()
        #expect(session.board[cell] == 0)
        #expect(session.canRedo)

        session.redo()
        #expect(session.board[cell] == 5)
    }

    @Test("a new move clears the redo branch")
    func mutationClearsRedo() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.select(cell)
        session.input(5)
        session.undo()
        #expect(session.canRedo)

        session.input(6)
        #expect(!session.canRedo, "a fresh move should discard the redo branch")
    }

    @Test("undo restores notes as well as values")
    func undoRestoresNotes() {
        let session = session()
        let cell = firstEmptyCell(session)

        session.toggleNotes()
        session.select(cell)
        session.input(3)
        session.toggleNotes()
        session.input(5)

        session.undo()
        #expect(session.board[cell] == 0)
        #expect(Candidates.digits(session.notes(at: cell)) == [3], "notes cleared by a placement should come back")
    }

    @Test("history is capped and drops the oldest entries")
    func historyCap() {
        let session = session()
        let cells = session.board.emptyCells

        // More edits than the cap, so the earliest are discarded.
        for step in 0..<150 {
            session.select(cells[step % cells.count])
            session.input((step % 9) + 1)
        }
        var undone = 0
        while session.canUndo {
            session.undo()
            undone += 1
        }
        #expect(undone == 100, "the history should hold exactly its cap, got \(undone)")
    }

    @Test("undo and redo on an untouched board do nothing")
    func historyEdges() {
        let session = session()
        session.undo()
        session.redo()
        #expect(session.board == session.puzzle.puzzle)
    }

    // MARK: - Input modes

    @Test("digit-first arms a digit, then taps fill cells")
    func digitFirstMode() {
        let session = session()
        session.inputMode = .digitFirst

        session.input(7)
        #expect(session.armedDigit == 7)
        #expect(session.highlightedDigit == 7, "arming a digit should also highlight it")

        let cell = firstEmptyCell(session)
        session.select(cell)
        #expect(session.board[cell] == 7)
    }

    @Test("digit-first keeps the digit armed across several cells")
    func digitFirstStaysArmed() {
        let session = session()
        session.inputMode = .digitFirst
        session.input(4)

        let cells = Array(session.board.emptyCells.prefix(3))
        for cell in cells { session.select(cell) }

        #expect(cells.allSatisfy { session.board[$0] == 4 })
    }

    @Test("arming the same digit twice disarms it")
    func digitFirstDisarms() {
        let session = session()
        session.inputMode = .digitFirst
        session.input(4)
        session.input(4)

        #expect(session.armedDigit == nil)
        #expect(session.highlightedDigit == nil)
    }

    // MARK: - Modes

    @Test("long-press masks the row and column of a filled cell")
    func blindMode() {
        let session = session()
        let given = firstGiven(session)

        session.longPress(given)
        #expect(session.isBlindMode)

        let masked = session.blindedCells
        #expect(masked.count == 16, "eight in the row and eight in the column, less the cell itself")
        #expect(masked.contains(CellRef(row: given.row, col: (given.col + 1) % 9)))
        #expect(!masked.contains(given))
    }

    @Test("long-press on an empty cell does nothing")
    func blindModeNeedsAValue() {
        let session = session()
        session.longPress(firstEmptyCell(session))
        #expect(!session.isBlindMode)
    }

    @Test("selecting a cell cancels blind mode")
    func selectionCancelsBlindMode() {
        let session = session()
        session.longPress(firstGiven(session))
        #expect(session.isBlindMode)

        session.select(firstEmptyCell(session))
        #expect(!session.isBlindMode, "the mask is anchored to the old selection, so it must not survive")
    }

    @Test("double-tap highlights a digit everywhere, including notes")
    func highlightDigit() {
        let session = session()
        let given = firstGiven(session)
        let digit = session.board[given]

        session.doubleTap(given)
        #expect(session.highlightedDigit == digit)
        #expect(session.isHighlighted(given))

        // A pencilled candidate of the same digit should light up too.
        let empty = firstEmptyCell(session)
        session.select(empty)
        session.inputNote(digit)
        #expect(session.isHighlighted(empty))

        session.doubleTap(given)
        #expect(session.highlightedDigit == nil, "double-tapping again clears the highlight")
    }

    // MARK: - Keyboard navigation

    @Test("arrow movement starts at the top-left when nothing is selected")
    func moveFromNoSelection() {
        let session = session()
        session.moveSelection(rowDelta: 1, colDelta: 0)
        #expect(session.selection == CellRef(index: 0))
    }

    @Test("arrow movement walks the grid")
    func moveSelection() {
        let session = session()
        session.select(CellRef(row: 4, col: 4))

        session.moveSelection(rowDelta: -1, colDelta: 0)
        #expect(session.selection == CellRef(row: 3, col: 4))

        session.moveSelection(rowDelta: 0, colDelta: 1)
        #expect(session.selection == CellRef(row: 3, col: 5))
    }

    @Test("movement clamps at the edges rather than wrapping")
    func moveSelectionClamps() {
        let session = session()

        session.select(CellRef(row: 0, col: 0))
        session.moveSelection(rowDelta: -1, colDelta: -1)
        #expect(session.selection == CellRef(row: 0, col: 0), "the top-left corner should not wrap round")

        session.select(CellRef(row: 8, col: 8))
        session.moveSelection(rowDelta: 1, colDelta: 1)
        #expect(session.selection == CellRef(row: 8, col: 8))
    }

    @Test("moving cancels blind mode")
    func moveCancelsBlindMode() {
        let session = session()
        session.longPress(firstGiven(session))
        #expect(session.isBlindMode)

        session.moveSelection(rowDelta: 1, colDelta: 0)
        #expect(!session.isBlindMode)
    }

    @Test("the highlight key acts on the selected cell")
    func highlightFromKeyboard() {
        let session = session()
        let given = firstGiven(session)

        session.select(given)
        session.toggleHighlightOnSelection()
        #expect(session.highlightedDigit == session.board[given])

        session.toggleHighlightOnSelection()
        #expect(session.highlightedDigit == nil)
    }

    @Test("the highlight key does nothing without a selection")
    func highlightNeedsSelection() {
        let session = session()
        session.toggleHighlightOnSelection()
        #expect(session.highlightedDigit == nil)
    }

    // MARK: - Derived

    @Test("conflicts report both halves of a duplicate pair")
    func conflicts() {
        let session = session()
        #expect(session.conflicts.isEmpty)

        let row = (0..<SudokuKit.Grid.size).map { CellRef(row: 0, col: $0) }
        guard let given = row.first(where: { session.isGiven($0) }),
            let target = row.first(where: { session.board[$0] == 0 })
        else { return }

        session.select(target)
        session.input(session.board[given])

        #expect(session.conflicts.contains(target))
        #expect(session.conflicts.contains(given))
    }

    /// The web app makes error highlighting opt-in (`lib/settings.ts:36`).
    /// Turning it off must actually hide conflicts, not merely restyle them.
    @Test("conflicts stay hidden when the setting is off")
    func conflictsRespectTheSetting() {
        let session = session(showsConflicts: false)
        let row = (0..<SudokuKit.Grid.size).map { CellRef(row: 0, col: $0) }
        guard let given = row.first(where: { session.isGiven($0) }),
            let target = row.first(where: { session.board[$0] == 0 })
        else { return }

        session.select(target)
        session.input(session.board[given])
        #expect(session.conflicts.isEmpty)
    }

    @Test("remaining counts track what is left to place")
    func remainingCounts() {
        let session = session()
        let cell = firstEmptyCell(session)
        let digit = session.puzzle.solution[cell]
        let before = session.remainingCounts[digit] ?? 0

        session.select(cell)
        session.input(digit)
        #expect(session.remainingCounts[digit] == before - 1)

        solve(session)
        #expect(session.remainingCounts.values.allSatisfy { $0 == 0 })
    }

    @Test("a full but wrong unit is reported as incorrect")
    func incorrectUnits() {
        let session = session()
        #expect(session.incorrectUnits.isEmpty)

        // Fill row 0 from the solution, then break one cell.
        let row = (0..<SudokuKit.Grid.size).map { CellRef(row: 0, col: $0) }
        for cell in row where session.board[cell] == 0 {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
        guard let editable = row.first(where: { !session.isGiven($0) }) else { return }
        session.select(editable)
        let wrong = session.board[row[0]] == session.board[editable] ? 0 : session.board[row[0]]
        if wrong != 0 {
            session.input(wrong)
            #expect(session.incorrectUnits.contains(.row(0)))
        }
    }

    // MARK: - Celebration

    /// Loading a board must not set off a fanfare for work done earlier — the
    /// first computation records a baseline and celebrates nothing.
    @Test("only newly completed units celebrate")
    func celebration() {
        let session = session()
        #expect(session.celebratingUnits.isEmpty)

        let row = (0..<SudokuKit.Grid.size).map { CellRef(row: 0, col: $0) }
        for cell in row where session.board[cell] == 0 {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }

        #expect(session.celebratingUnits.contains(.row(0)), "completing a row should celebrate it")

        session.clearCelebration()
        #expect(session.celebratingUnits.isEmpty)
    }

    // MARK: - Timer

    @Test("the clock advances only while running")
    func timer() {
        let session = session()
        session.tick(.seconds(5))
        #expect(session.elapsedSeconds == 5)

        session.pause()
        session.tick(.seconds(10))
        #expect(session.elapsedSeconds == 5, "a paused clock must not advance")

        session.resume()
        session.tick(.seconds(3))
        #expect(session.elapsedSeconds == 8)
    }

    @Test("time is formatted as minutes and seconds")
    func timeFormatting() {
        let session = session()
        session.tick(.seconds(65))
        #expect(session.formattedTime == "1:05")
    }

    // MARK: - Inactivity

    @Test("the offer to pause arrives after the threshold")
    func idlePrompt() {
        let session = session()
        session.inactivityMinutes = 5

        session.tick(.seconds(299))
        #expect(!session.isIdlePromptDue)

        session.tick(.seconds(1))
        #expect(session.isIdlePromptDue)
    }

    @Test("any move resets the idle clock")
    func interactionResetsIdle() {
        let session = session()
        session.inactivityMinutes = 1

        session.tick(.seconds(59))
        session.select(firstEmptyCell(session))
        session.tick(.seconds(30))

        #expect(!session.isIdlePromptDue, "selecting a cell should count as being there")
    }

    @Test("placing a digit resets the idle clock")
    func inputResetsIdle() {
        let session = session()
        session.inactivityMinutes = 1
        session.select(firstEmptyCell(session))

        session.tick(.seconds(59))
        session.input(5)
        session.tick(.seconds(30))

        #expect(!session.isIdlePromptDue)
    }

    @Test("accepting the offer pauses the clock")
    func acceptIdlePause() {
        let session = session()
        session.inactivityMinutes = 1
        session.tick(.seconds(60))

        session.acceptIdlePause()
        #expect(session.isPaused)
        #expect(!session.isIdlePromptDue)

        session.tick(.seconds(600))
        #expect(session.elapsedSeconds == 60, "a paused clock must not run on")
    }

    /// A prompt that reappears the instant it is dismissed is worse than none.
    @Test("declining buys another full interval")
    func declineIdlePause() {
        let session = session()
        session.inactivityMinutes = 1
        session.tick(.seconds(60))

        session.declineIdlePause()
        #expect(!session.isIdlePromptDue)

        session.tick(.seconds(59))
        #expect(!session.isIdlePromptDue)
        session.tick(.seconds(1))
        #expect(session.isIdlePromptDue, "the offer should return after another full interval")
    }

    @Test("the offer never appears when it could not help")
    func idlePromptSuppressed() {
        let disabled = session()
        disabled.inactivityMinutes = 0
        disabled.tick(.seconds(3600))
        #expect(!disabled.isIdlePromptDue, "0 minutes means never")

        let paused = session()
        paused.inactivityMinutes = 1
        paused.pause()
        paused.tick(.seconds(600))
        #expect(!paused.isIdlePromptDue, "already paused")

        let finished = session()
        finished.inactivityMinutes = 1
        solve(finished)
        finished.tick(.seconds(600))
        #expect(!finished.isIdlePromptDue, "already finished")
    }

    // MARK: - Winning

    @Test("solving raises the win summary, which can be dismissed")
    func winSummary() {
        let session = session()
        #expect(!session.showsWinSummary)

        solve(session)
        #expect(session.showsWinSummary)

        session.dismissWinSummary()
        #expect(!session.showsWinSummary, "dismissing should leave the finished board visible")
        #expect(session.isSolved, "and the puzzle is still solved")
    }

    @Test("restart clears the win state")
    func restartAfterWinning() {
        let session = session()
        solve(session)
        session.restart()

        #expect(!session.showsWinSummary)
        #expect(session.finishedAt == nil)
        #expect(!session.isSolved)
    }

    // MARK: - Hints

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

    // MARK: - Completion

    @Test("solving stops the clock and records the finish")
    func solving() {
        let session = session()
        solve(session)

        #expect(session.isSolved)
        #expect(session.board == session.puzzle.solution)
        #expect(session.finishedAt != nil)
        #expect(session.isPaused, "the clock should stop the moment the puzzle is finished")
    }

    @Test("a full but wrong board is not a solve")
    func fullButWrongIsNotSolved() {
        let session = session()
        var spoiled = false

        for index in 0..<SudokuKit.Grid.cellCount where session.board[index] == 0 {
            let cell = CellRef(index: index)
            session.select(cell)
            let correct = session.puzzle.solution[cell]
            if spoiled {
                session.input(correct)
            } else {
                session.input(correct == 1 ? 2 : 1)
                spoiled = true
            }
        }

        #expect(session.board.isFull)
        #expect(!session.isSolved, "a filled board that breaks the rules is wrong, not finished")
        #expect(session.finishedAt == nil)
    }
}
