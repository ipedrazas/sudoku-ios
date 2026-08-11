import SudokuKit
import SwiftUI

/// The 9×9 board.
struct BoardView: View {
    @Bindable var session: GameSession

    /// The web app uses a 450 ms long-press for blind mode and a 300 ms
    /// double-tap window for digit highlighting (`Board.tsx:126`, `:144`).
    /// Porting the timings keeps the feel identical for anyone who plays both.
    private static let longPressDuration = 0.45

    /// Ties the rotor entries below to the cells they point at.
    @Namespace private var cells

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<SudokuKit.Grid.size, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<SudokuKit.Grid.size, id: \.self) { column in
                        cellView(CellRef(row: row, col: column))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(boxLines)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.45), lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sudoku board")
        // Ordered by how often each is wanted: what is left to do first, what is
        // wrong second, then the structural jumps.
        .accessibilityRotor("Empty cells") {
            ForEach(session.board.emptyCells, id: \.index) { cell in
                AccessibilityRotorEntry(BoardAccessibility.rotorLabel(for: cell), cell.index, in: cells)
            }
        }
        // Only populated when the player asked to be told about mistakes:
        // `session.conflicts` is empty when the setting is off, so a rotor
        // listing them cannot hand back what they turned it off to avoid.
        .accessibilityRotor("Conflicts") {
            ForEach(BoardAccessibility.sortedConflicts(in: session), id: \.index) { cell in
                AccessibilityRotorEntry(BoardAccessibility.rotorLabel(for: cell), cell.index, in: cells)
            }
        }
        .accessibilityRotor("Rows") {
            ForEach(0..<SudokuKit.Grid.size, id: \.self) { row in
                AccessibilityRotorEntry("Row \(row + 1)", CellRef(row: row, col: 0).index, in: cells)
            }
        }
        .accessibilityRotor("Columns") {
            ForEach(0..<SudokuKit.Grid.size, id: \.self) { column in
                AccessibilityRotorEntry("Column \(column + 1)", CellRef(row: 0, col: column).index, in: cells)
            }
        }
        .accessibilityRotor("Boxes") {
            ForEach(0..<SudokuKit.Grid.size, id: \.self) { box in
                AccessibilityRotorEntry("Box \(box + 1)", BoardAccessibility.firstCell(ofBox: box).index, in: cells)
            }
        }
    }

    // MARK: - Rotors

    // Ways through the grid other than one cell at a time.
    //
    // Swiping through 81 cells to reach the one you want is not navigation, it
    // is endurance — and a Sudoku player does not think in reading order anyway.
    // They think "the middle box", "the row I am filling", "where are the empty
    // ones". The rotors above are the equivalent of what a sighted player does
    // with their eyes in a fraction of a second.

    // MARK: - Cells

    private func cellView(_ cell: CellRef) -> some View {
        let value = session.board[cell]
        let state = CellState(session: session, cell: cell)

        return ZStack {
            state.background
            if value != 0 {
                Text(String(value))
                    .font(.system(size: 22, weight: state.isGiven ? .semibold : .regular, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(state.foreground)
            } else if session.notes(at: cell) != 0 {
                NotesView(mask: session.notes(at: cell), highlighted: session.highlightedDigit)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay(cellBorder)
        .overlay(state.conflictUnderline)
        .overlay(state.unitOutline)
        .overlay(state.hintOutline)
        .overlay(selectionRing(isSelected: state.isSelected))
        // Blind mode masks the contents but keeps the cell tappable: the point
        // is to stop the player reading the line, not to lock them out of it.
        .opacity(state.isBlinded ? 0 : 1)
        .background(state.isBlinded ? Color.secondary.opacity(0.25) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { session.doubleTap(cell) }
        .onTapGesture { session.select(cell) }
        .onLongPressGesture(minimumDuration: Self.longPressDuration) { session.longPress(cell) }
        .accessibilityElement()
        .accessibilityLabel(BoardAccessibility.label(for: cell, in: session))
        .accessibilityIdentifier("cell.\(cell.index)")
        .accessibilityAddTraits(state.isSelected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityAction { session.select(cell) }
        // What the rotors above point at. Without this the entries resolve to
        // nothing and the rotor silently does not appear.
        .accessibilityRotorEntry(id: cell.index, in: cells)
    }

    private var cellBorder: some View {
        Rectangle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
    }

    private func selectionRing(isSelected: Bool) -> some View {
        Rectangle()
            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
    }

    /// The 3×3 box boundaries, drawn over the thin cell grid.
    private var boxLines: some View {
        GeometryReader { proxy in
            let step = proxy.size.width / CGFloat(SudokuKit.Grid.size)
            Path { path in
                for index in stride(from: SudokuKit.Grid.boxSize, to: SudokuKit.Grid.size, by: SudokuKit.Grid.boxSize) {
                    let offset = step * CGFloat(index)
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: offset))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: offset))
                }
            }
            .stroke(Color.primary.opacity(0.45), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

}

// MARK: - Cell state

/// Everything the look of one cell depends on, resolved once.
@MainActor
private struct CellState {
    let isGiven: Bool
    let isSelected: Bool
    let isConflict: Bool
    let isHighlighted: Bool
    let isBlinded: Bool
    let isCelebrating: Bool
    let isIncorrect: Bool
    /// The cell a hint is actually about.
    let isHintSubject: Bool
    /// A cell in a unit the hint is reasoning over — the row a locked candidate
    /// is claimed on, the two rows of an X-wing.
    let isHintContext: Bool

    init(session: GameSession, cell: CellRef) {
        isGiven = session.isGiven(cell)
        isSelected = session.selection == cell
        isConflict = session.conflicts.contains(cell)
        isHighlighted = session.isHighlighted(cell)
        isBlinded = session.blindedCells.contains(cell)
        isCelebrating = session.celebratingUnits.contains { $0.cells.contains(cell) }
        isIncorrect = session.incorrectUnits.contains { $0.cells.contains(cell) }
        isHintSubject = session.hintCells.contains(cell)
        isHintContext = !isHintSubject && session.hintUnitCells.contains(cell)
    }

    /// Givens read as the puzzle; entries read as the player's own work.
    var foreground: Color {
        if isConflict { return .red }
        return isGiven ? .primary : .accentColor
    }

    @ViewBuilder var background: some View {
        // A hint outranks the ambient highlights: it was asked for, and the
        // whole point of showing it is that the eye goes there.
        if isHintSubject {
            Color.yellow.opacity(0.45)
        } else if isSelected {
            Color.accentColor.opacity(0.22)
        } else if isConflict {
            Color.red.opacity(0.14)
        } else if isCelebrating {
            Color.green.opacity(0.3)
        } else if isIncorrect {
            Color.orange.opacity(0.12)
        } else if isHintContext {
            Color.yellow.opacity(0.16)
        } else if isHighlighted {
            Color.accentColor.opacity(0.1)
        } else {
            Color.clear
        }
    }

    /// Colour is never the only signal.
    ///
    /// Roughly one man in twelve cannot separate the red of a conflict from the
    /// green of a completed unit, and both are drawn over the same board at the
    /// same time. So every state that means something carries a shape as well as
    /// a colour, and the shapes are chosen to be distinguishable from each other
    /// rather than merely present:
    ///
    /// | State | Colour | Shape |
    /// |---|---|---|
    /// | conflict | red | underline beneath the digit |
    /// | complete unit | green | full border |
    /// | full but wrong | orange | dashed border |
    /// | hint subject | yellow | rounded outline |
    ///
    /// Selection has its own ring already, and the digit highlight is a
    /// convenience rather than a claim about correctness, so neither needs one.
    @ViewBuilder var hintOutline: some View {
        if isHintSubject {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.orange, lineWidth: 2)
        }
    }

    /// A complete unit is bordered; a full-but-wrong one is bordered in dashes.
    ///
    /// A dash pattern rather than a second colour, because the two states are
    /// adjacent in meaning — both say "this unit is full" — and differ only in
    /// whether it is right. That difference has to survive being seen in
    /// greyscale.
    @ViewBuilder var unitOutline: some View {
        if isCelebrating {
            Rectangle()
                .strokeBorder(Color.green, lineWidth: 1.5)
        } else if isIncorrect {
            Rectangle()
                .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        }
    }

    /// The conflict underline, drawn under the digit rather than around the cell
    /// so it cannot be confused with the unit borders above.
    @ViewBuilder var conflictUnderline: some View {
        if isConflict {
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 3)
            }
        }
    }
}

// MARK: - Notes

/// Candidate marks, laid out where the digit would sit on a numeric keypad, so
/// a given digit is always in the same corner and can be found without reading.
private struct NotesView: View {
    let mask: UInt16
    let highlighted: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        let digit = row * 3 + column + 1
                        Text(mask & Candidates.bit(digit) != 0 ? String(digit) : " ")
                            .font(.system(size: 9, weight: highlighted == digit ? .bold : .regular))
                            .foregroundStyle(highlighted == digit ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(1)
    }
}
