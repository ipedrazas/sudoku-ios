import Foundation
import SudokuKit

/// What the board says to VoiceOver.
///
/// Separated from `BoardView` because these are words, not layout — and words
/// are the part worth testing. A VoiceOver regression is invisible to everyone
/// who does not use VoiceOver, including whoever reviews the change: the day
/// conflicts stop being announced, every screenshot still looks perfect.
@MainActor
enum BoardAccessibility {

    /// Position first, then contents, then anything wrong.
    ///
    /// Position leads because a player navigating the grid needs to know where
    /// they are before what is there. State comes last because it is the part
    /// that changes as they play, and a label whose *end* changes is far easier
    /// to follow than one whose beginning does.
    ///
    /// Everything the board says in colour is said here in words. A sighted
    /// player sees a red digit and knows it clashes; without this, a VoiceOver
    /// player would have to work out the whole grid to discover the same thing —
    /// which is not a harder game, it is a different and worse one.
    static func label(for cell: CellRef, in session: GameSession) -> String {
        var parts = [String(localized: "row \(cell.row + 1), column \(cell.col + 1)")]

        let value = session.board[cell]
        if value != 0 {
            parts.append(String(value))
            if session.isGiven(cell) { parts.append(String(localized: "given")) }
        } else {
            let notes = Candidates.digits(session.notes(at: cell))
            parts.append(
                notes.isEmpty
                    ? String(localized: "empty")
                    : String(localized: "notes \(notes.map(String.init).joined(separator: ", "))")
            )
        }

        // `session.conflicts` is empty when mistake highlighting is off, so this
        // cannot announce something the board is not drawing. The setting has to
        // mean one thing whether or not you can see the screen.
        if session.conflicts.contains(cell) { parts.append(String(localized: "conflicts")) }
        if session.hintCells.contains(cell) { parts.append(String(localized: "hint")) }

        // The box is deliberately absent. It is derivable from the row and
        // column, and saying it on all 81 cells adds a word to every swipe to
        // answer a question only asked when navigating by box — which is what
        // the rotor is for.
        return parts.joined(separator: ", ")
    }

    /// What a rotor entry is called: position only. The cell's own label reads
    /// the contents once VoiceOver lands on it, and hearing them twice in a row
    /// is how a rotor stops being faster than swiping.
    static func rotorLabel(for cell: CellRef) -> String {
        String(localized: "Row \(cell.row + 1), column \(cell.col + 1)")
    }

    /// The top-left cell of a box, which is where a sighted player starts
    /// reading one.
    static func firstCell(ofBox box: Int) -> CellRef {
        CellRef(
            row: (box / SudokuKit.Grid.boxSize) * SudokuKit.Grid.boxSize,
            col: (box % SudokuKit.Grid.boxSize) * SudokuKit.Grid.boxSize
        )
    }

    /// Conflicts in reading order.
    ///
    /// Sorted rather than taken straight from the `Set`, because a rotor whose
    /// entries reorder between passes is worse than no rotor: "next" has to mean
    /// the same thing twice running.
    static func sortedConflicts(in session: GameSession) -> [CellRef] {
        session.conflicts.sorted { $0.index < $1.index }
    }
}
