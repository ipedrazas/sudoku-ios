import SudokuKit
import SwiftUI

/// The 9×9 board.
struct BoardView: View {
    @Bindable var session: GameSession

    /// The web app uses a 450 ms long-press for blind mode and a 300 ms
    /// double-tap window for digit highlighting (`Board.tsx:126`, `:144`).
    /// Porting the timings keeps the feel identical for anyone who plays both.
    private static let longPressDuration = 0.45

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
    }

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
        .accessibilityLabel(label(cell: cell, value: value, isGiven: state.isGiven))
        .accessibilityIdentifier("cell.\(cell.index)")
        .accessibilityAddTraits(state.isSelected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityAction { session.select(cell) }
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

    /// VoiceOver reads position first, then contents — a player navigating the
    /// grid needs to know where they are before what is there. A rotor for
    /// row/column/box navigation follows in Phase 9 (P9-1).
    private func label(cell: CellRef, value: Int, isGiven: Bool) -> String {
        let position = "row \(cell.row + 1), column \(cell.col + 1)"
        if value != 0 { return "\(position), \(value)\(isGiven ? ", given" : "")" }

        let notes = Candidates.digits(session.notes(at: cell))
        guard notes.isEmpty else {
            return "\(position), notes \(notes.map(String.init).joined(separator: ", "))"
        }
        return "\(position), empty"
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

    init(session: GameSession, cell: CellRef) {
        isGiven = session.isGiven(cell)
        isSelected = session.selection == cell
        isConflict = session.conflicts.contains(cell)
        isHighlighted = session.isHighlighted(cell)
        isBlinded = session.blindedCells.contains(cell)
        isCelebrating = session.celebratingUnits.contains { $0.cells.contains(cell) }
        isIncorrect = session.incorrectUnits.contains { $0.cells.contains(cell) }
    }

    /// Givens read as the puzzle; entries read as the player's own work.
    var foreground: Color {
        if isConflict { return .red }
        return isGiven ? .primary : .accentColor
    }

    @ViewBuilder var background: some View {
        if isSelected {
            Color.accentColor.opacity(0.22)
        } else if isConflict {
            Color.red.opacity(0.14)
        } else if isCelebrating {
            Color.green.opacity(0.3)
        } else if isIncorrect {
            Color.orange.opacity(0.12)
        } else if isHighlighted {
            Color.accentColor.opacity(0.1)
        } else {
            Color.clear
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
