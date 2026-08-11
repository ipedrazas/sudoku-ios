import Foundation
import SudokuKit
import Testing

@testable import SudokuApp

/// What the board says out loud.
///
/// The labels are built from session state, so they are testable without a view
/// — and worth testing, because a VoiceOver regression is invisible to everyone
/// who does not use VoiceOver. A sighted reviewer looking at these screens would
/// see nothing wrong on the day conflicts stopped being announced.
@Suite("Accessibility")
@MainActor
struct AccessibilityTests {

    private func session(
        _ difficulty: Difficulty = .easy,
        seed: UInt64 = 1,
        showsConflicts: Bool = true
    ) -> GameSession {
        var rng = SeededRandom(seed: seed)
        return GameSession(puzzle: Generator.generate(difficulty, using: &rng), showsConflicts: showsConflicts)
    }

    /// The digit already in this cell's row — guaranteed to clash.
    private func clashingDigit(for cell: CellRef, in session: GameSession) -> Int {
        (0..<SudokuKit.Grid.size)
            .map { CellRef(row: cell.row, col: $0) }
            .first { session.board[$0] != 0 }
            .map { session.board[$0] } ?? 1
    }

    @Test("an empty cell reads as its position, then empty")
    func emptyCell() {
        let session = session()
        let cell = session.board.emptyCells[0]

        let label = BoardAccessibility.label(for: cell, in: session)

        #expect(label.hasPrefix("row \(cell.row + 1), column \(cell.col + 1)"))
        #expect(label.hasSuffix("empty"))
    }

    @Test("a given reads as its digit and says so")
    func givenCell() throws {
        let session = session()
        let cell = try #require((0..<SudokuKit.Grid.cellCount).map(CellRef.init(index:)).first { session.isGiven($0) })

        let label = BoardAccessibility.label(for: cell, in: session)

        #expect(label.contains(", \(session.board[cell]),"))
        #expect(label.hasSuffix("given"))
    }

    @Test("pencil marks are read out rather than reported as empty")
    func notedCell() {
        let session = session()
        let cell = session.board.emptyCells[0]
        session.select(cell)
        session.toggleNotes()
        session.input(3)
        session.input(7)

        let label = BoardAccessibility.label(for: cell, in: session)

        #expect(label.contains("notes 3, 7"))
        #expect(!label.contains("empty"))
    }

    @Test("a conflict is announced, because a sighted player can see it")
    func conflictIsAnnounced() {
        let session = session()
        let cell = session.board.emptyCells[0]
        session.select(cell)
        session.input(clashingDigit(for: cell, in: session))

        #expect(BoardAccessibility.label(for: cell, in: session).contains("conflicts"))
    }

    @Test("with mistake highlighting off, nothing is announced either")
    func conflictStaysQuietWhenHighlightingIsOff() {
        // The board does not draw it, so the label must not say it. Announcing a
        // conflict VoiceOver users can hear but sighted players cannot see would
        // make the setting mean two different things.
        let session = session(showsConflicts: false)
        let cell = session.board.emptyCells[0]
        session.select(cell)
        session.input(clashingDigit(for: cell, in: session))

        #expect(!BoardAccessibility.label(for: cell, in: session).contains("conflicts"))
    }

    @Test("the cell a hint is about says so")
    func hintIsAnnounced() throws {
        let session = session()
        let hint = session.hint(at: .nudge)
        session.show(hint)
        let cell = try #require(hint.cells.first)

        #expect(BoardAccessibility.label(for: cell, in: session).contains("hint"))
    }

    @Test("the box is not read on every cell")
    func boxIsNotInEveryLabel() {
        // Derivable from the row and column, and 81 cells × one extra word is a
        // slower swipe through the whole grid for something only wanted when
        // navigating by box — which the rotor does.
        let session = session()
        let label = BoardAccessibility.label(for: CellRef(row: 4, col: 4), in: session)

        #expect(!label.contains("box"))
    }

    @Test("a rotor entry names the position and stops there")
    func rotorEntryLabel() {
        // The cell's own label reads the contents the moment VoiceOver lands on
        // it. Saying them in the rotor entry too is how a rotor stops being
        // faster than swiping.
        #expect(BoardAccessibility.rotorLabel(for: CellRef(row: 2, col: 6)) == "Row 3, column 7")
    }

    @Test("each box entry points at that box's top-left cell")
    func boxEntries() {
        #expect(BoardAccessibility.firstCell(ofBox: 0) == CellRef(row: 0, col: 0))
        #expect(BoardAccessibility.firstCell(ofBox: 4) == CellRef(row: 3, col: 3))
        #expect(BoardAccessibility.firstCell(ofBox: 8) == CellRef(row: 6, col: 6))

        // Every entry must land in the box it names, or the rotor is lying.
        for box in 0..<SudokuKit.Grid.size {
            #expect(BoardAccessibility.firstCell(ofBox: box).box == box)
        }
    }

    @Test("the conflicts rotor lists cells in reading order")
    func conflictsAreSorted() {
        // A rotor whose entries reorder as a Set re-hashes would be worse than
        // no rotor: "next" has to mean the same thing twice running.
        let session = session()
        for cell in session.board.emptyCells.prefix(6) {
            session.select(cell)
            session.input(clashingDigit(for: cell, in: session))
        }

        let conflicts = BoardAccessibility.sortedConflicts(in: session)

        #expect(!conflicts.isEmpty)
        #expect(conflicts == conflicts.sorted { $0.index < $1.index })
    }
}
