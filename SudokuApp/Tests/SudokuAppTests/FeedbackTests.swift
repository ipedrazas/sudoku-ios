import Foundation
import SudokuKit
import Testing

@testable import SudokuApp

/// What the session says happened.
///
/// The haptics and sounds themselves are three lines of `UIFeedbackGenerator`
/// and `AVAudioPlayer` with nothing to assert about them — but *which* event
/// fires, and when one deliberately does not, is real behaviour with real edge
/// cases. That is what is tested here; `Feedback` is left alone on purpose.
@Suite("Feedback events")
@MainActor
struct FeedbackTests {

    /// Collects what a session emits, in order.
    @MainActor
    private final class Recorder {
        var events: [GameEvent] = []

        func attach(to session: GameSession) {
            session.didEmit = { [weak self] event in self?.events.append(event) }
        }
    }

    private func session(
        _ difficulty: Difficulty = .easy,
        seed: UInt64 = 1,
        showsConflicts: Bool = true
    ) -> GameSession {
        var rng = SeededRandom(seed: seed)
        return GameSession(puzzle: Generator.generate(difficulty, using: &rng), showsConflicts: showsConflicts)
    }

    @Test("filling a cell correctly is a placement")
    func placement() {
        let session = session()
        let recorder = Recorder()
        recorder.attach(to: session)

        let cell = session.board.emptyCells[0]
        session.select(cell)
        session.input(session.puzzle.solution[cell])

        #expect(recorder.events == [.placed])
    }

    @Test("a digit that clashes with one already there is a conflict")
    func conflict() throws {
        let session = session()
        let recorder = Recorder()
        recorder.attach(to: session)

        // A digit already in this cell's row, placed again in the empty cell —
        // guaranteed to clash, and guaranteed to exist because a row of nine has
        // at least one given in every puzzle this generator produces.
        let cell = session.board.emptyCells[0]
        let clashing = try #require(
            (0..<SudokuKit.Grid.size)
                .map { CellRef(row: cell.row, col: $0) }
                .first { session.board[$0] != 0 }
                .map { session.board[$0] }
        )

        session.select(cell)
        session.input(clashing)

        #expect(recorder.events == [.conflicted])
    }

    @Test("with mistake highlighting off, a clash is just a placement")
    func conflictStaysQuietWhenHighlightingIsOff() throws {
        // The setting is opt-in, and the whole point of leaving it off is not
        // being told. A buzz on a wrong digit would hand back exactly the
        // information the player declined.
        let session = session(showsConflicts: false)
        let recorder = Recorder()
        recorder.attach(to: session)

        let cell = session.board.emptyCells[0]
        let clashing = try #require(
            (0..<SudokuKit.Grid.size)
                .map { CellRef(row: cell.row, col: $0) }
                .first { session.board[$0] != 0 }
                .map { session.board[$0] }
        )

        session.select(cell)
        session.input(clashing)

        #expect(recorder.events == [.placed])
    }

    @Test("completing a unit outranks the placement that completed it")
    func unitCompletion() throws {
        let session = session()
        let recorder = Recorder()

        // Fill a whole row but for one cell, then attach — so the only event
        // recorded is the one that closes it.
        let row = try #require(
            (0..<SudokuKit.Grid.size).first { row in
                (0..<SudokuKit.Grid.size).contains { session.board[CellRef(row: row, col: $0)] == 0 }
            })
        let empties = (0..<SudokuKit.Grid.size)
            .map { CellRef(row: row, col: $0) }
            .filter { session.board[$0] == 0 }

        for cell in empties.dropLast() {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }

        recorder.attach(to: session)
        let last = try #require(empties.last)
        session.select(last)
        session.input(session.puzzle.solution[last])

        #expect(recorder.events == [.unitCompleted])
    }

    @Test("solving outranks everything, and fires exactly once")
    func solving() {
        let session = session()
        let recorder = Recorder()

        for cell in session.board.emptyCells.dropLast() {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }

        recorder.attach(to: session)
        // swiftlint:disable:next force_unwrapping
        let last = session.board.emptyCells.last!
        session.select(last)
        session.input(session.puzzle.solution[last])

        // The final move completes a row, a column and a box as well as the
        // grid. One feeling, not four.
        #expect(recorder.events == [.solved])
    }

    @Test("erasing, undoing and auto-filling notes are not moves")
    func silentChanges() {
        let session = session()
        let recorder = Recorder()

        let cell = session.board.emptyCells[0]
        session.select(cell)
        session.input(session.puzzle.solution[cell])

        recorder.attach(to: session)

        // Tapping the same digit again erases it.
        session.input(session.puzzle.solution[cell])
        session.undo()
        session.redo()
        session.erase()
        session.autoFillNotes()
        session.toggleNotes()
        session.restart()

        #expect(recorder.events.isEmpty)
    }

    @Test("a pencil mark is not a placement")
    func pencilMarksAreSilent() {
        let session = session()
        let recorder = Recorder()
        recorder.attach(to: session)

        session.select(session.board.emptyCells[0])
        session.toggleNotes()
        session.input(5)

        #expect(recorder.events.isEmpty)
    }

    @Test("a revealed hint feels like the placement it is")
    func revealedHint() {
        let session = session()
        let recorder = Recorder()
        recorder.attach(to: session)

        let hint = session.hint(at: .reveal)
        session.applyHint(hint)

        #expect(recorder.events == [.placed])
    }

    @Test("every event has a sound file to play")
    func soundAssetsExist() {
        // The names are a handshake between this enum and a generator script
        // that is only ever run by hand. A typo in either one is silent at
        // build time and silent at run time, which is the worst combination.
        for event in [GameEvent.placed, .conflicted, .unitCompleted, .solved] {
            let url = Bundle.main.url(forResource: event.soundName, withExtension: "caf")
            #expect(url != nil, "no sound asset for \(event)")
        }
    }
}
