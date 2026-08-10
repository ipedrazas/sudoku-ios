import SudokuKit
import SwiftUI

/// The 9×9 board.
///
/// Tracer-bullet form: givens, entries, selection and conflicts. Pencil marks,
/// unit-completion celebration, blind mode and digit highlighting arrive in
/// Phase 3 (P3-2, P3-5, P3-7).
struct BoardView: View {
    @Bindable var session: GameSession

    /// Box boundaries are drawn as thicker lines rather than separate borders so
    /// the 3×3 structure reads at a glance without doubling every internal edge.
    private let thinLine: CGFloat = 1
    private let thickLine: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / CGFloat(SudokuKit.Grid.size)

            VStack(spacing: 0) {
                ForEach(0..<SudokuKit.Grid.size, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<SudokuKit.Grid.size, id: \.self) { column in
                            cellView(row: row, column: column, size: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .overlay(gridLines(cell: cell))
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.5), lineWidth: thickLine)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sudoku board")
    }

    private func cellView(row: Int, column: Int, size: CGFloat) -> some View {
        let cell = CellRef(row: row, col: column)
        let value = session.board[cell]
        let isGiven = session.isGiven(cell)
        let isSelected = session.selection == cell
        let isConflict = session.conflicts.contains(cell)

        return Button {
            session.select(cell)
        } label: {
            Text(value == 0 ? " " : String(value))
                .font(.system(size: size * 0.5, weight: isGiven ? .semibold : .regular, design: .rounded))
                .foregroundStyle(foreground(isGiven: isGiven, isConflict: isConflict))
                .frame(width: size, height: size)
                .background(background(isSelected: isSelected, isConflict: isConflict))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(cell: cell, value: value, isGiven: isGiven))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func foreground(isGiven: Bool, isConflict: Bool) -> Color {
        if isConflict { return .red }
        // Givens read as the puzzle; entries read as the player's own work.
        return isGiven ? .primary : .accentColor
    }

    private func background(isSelected: Bool, isConflict: Bool) -> Color {
        if isSelected { return .accentColor.opacity(0.25) }
        if isConflict { return .red.opacity(0.12) }
        return .clear
    }

    /// VoiceOver reads position first, then contents — a player navigating the
    /// grid needs to know where they are before what is there. Fleshed out in
    /// Phase 9 (P9-1) with a rotor for row/column/box navigation.
    private func label(cell: CellRef, value: Int, isGiven: Bool) -> String {
        let position = "row \(cell.row + 1), column \(cell.col + 1)"
        guard value != 0 else { return "\(position), empty" }
        return "\(position), \(value)\(isGiven ? ", given" : "")"
    }

    private func gridLines(cell: CGFloat) -> some View {
        Path { path in
            for index in 1..<SudokuKit.Grid.size {
                let offset = cell * CGFloat(index)
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset, y: cell * CGFloat(SudokuKit.Grid.size)))
                path.move(to: CGPoint(x: 0, y: offset))
                path.addLine(to: CGPoint(x: cell * CGFloat(SudokuKit.Grid.size), y: offset))
            }
        }
        .stroke(Color.primary.opacity(0.2), lineWidth: thinLine)
        .overlay(
            Path { path in
                for index in stride(from: SudokuKit.Grid.boxSize, to: SudokuKit.Grid.size, by: SudokuKit.Grid.boxSize) {
                    let offset = cell * CGFloat(index)
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset, y: cell * CGFloat(SudokuKit.Grid.size)))
                    path.move(to: CGPoint(x: 0, y: offset))
                    path.addLine(to: CGPoint(x: cell * CGFloat(SudokuKit.Grid.size), y: offset))
                }
            }
            .stroke(Color.primary.opacity(0.5), lineWidth: thickLine)
        )
        .allowsHitTesting(false)
    }
}
