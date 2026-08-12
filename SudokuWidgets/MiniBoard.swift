import SwiftUI

/// A 9×9 grid at widget scale.
///
/// Not a reuse of `BoardView`: that one is interactive, tracks selection,
/// conflicts, pencil marks and celebrations, and every one of those is dead
/// weight in a process whose whole job is to draw a picture once. This draws
/// digits and lines, and knows the difference between a given and something the
/// player put there.
///
/// Widgets are rendered by the system, not by the app, and are flattened to an
/// image — so everything here has to be static, and no gesture, animation or
/// timer would survive anyway.
struct MiniBoard: View {

    /// The puzzle as dealt, and the board as it stands. Parsed once at
    /// construction: `String` is not randomly accessible, and indexing into one
    /// 81 times per cell is a quadratic walk to draw a square.
    private let givens: [Int]
    private let board: [Int]

    /// Set on the large widget, where there is room for it.
    private let showsDigits: Bool

    /// Both strings are 81 characters, `0` for empty. Anything shorter is padded
    /// with empties rather than refused — a widget that renders nothing because
    /// a string was truncated is a worse failure than one with a gap in it.
    init(givens: String, board: String, showsDigits: Bool = true) {
        self.givens = Self.digits(givens)
        self.board = Self.digits(board)
        self.showsDigits = showsDigits
    }

    private static func digits(_ text: String) -> [Int] {
        var values = text.map { $0.wholeNumberValue ?? 0 }
        if values.count < size * size {
            values += [Int](repeating: 0, count: size * size - values.count)
        }
        return values
    }

    private static let size = 9

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / CGFloat(Self.size)

            ZStack(alignment: .topLeading) {
                if showsDigits {
                    digits(cell: cell)
                } else {
                    filledCells(cell: cell)
                }
                lines(side: side, cell: cell)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Contents

    private func digits(cell: CGFloat) -> some View {
        ForEach(0..<(Self.size * Self.size), id: \.self) { index in
            let value = board[index]
            if value != 0 {
                Text(String(value))
                    // Scaled to the cell rather than a Dynamic Type style: the
                    // grid is a picture of a board, and a board whose digits
                    // grow out of their cells is not one.
                    .font(.system(size: cell * 0.62, weight: isGiven(index) ? .semibold : .regular))
                    .foregroundStyle(isGiven(index) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(index % Self.size) * cell, y: CGFloat(index / Self.size) * cell)
            }
        }
    }

    /// The small-widget form: no digits, just which cells are filled. At that
    /// size a 9-point numeral is a smudge, but the *pattern* of a board still
    /// reads as a Sudoku in progress.
    private func filledCells(cell: CGFloat) -> some View {
        ForEach(0..<(Self.size * Self.size), id: \.self) { index in
            let value = board[index]
            if value != 0 {
                RoundedRectangle(cornerRadius: cell * 0.18)
                    .fill(isGiven(index) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .padding(cell * 0.2)
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(index % Self.size) * cell, y: CGFloat(index / Self.size) * cell)
            }
        }
    }

    /// Thin lines between cells, thick ones between boxes — the only cue that
    /// says "Sudoku" rather than "grid".
    private func lines(side: CGFloat, cell: CGFloat) -> some View {
        Path { path in
            for index in 0...Self.size {
                let offset = CGFloat(index) * cell
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset, y: side))
                path.move(to: CGPoint(x: 0, y: offset))
                path.addLine(to: CGPoint(x: side, y: offset))
            }
        }
        .stroke(.quaternary, lineWidth: 0.5)
        .overlay {
            Path { path in
                for index in stride(from: 0, through: Self.size, by: 3) {
                    let offset = CGFloat(index) * cell
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset, y: side))
                    path.move(to: CGPoint(x: 0, y: offset))
                    path.addLine(to: CGPoint(x: side, y: offset))
                }
            }
            .stroke(.tertiary, lineWidth: 1)
        }
    }

    // MARK: - Reading the board

    private func isGiven(_ index: Int) -> Bool { givens[index] != 0 }

    /// One sentence rather than 81 cells. A widget is a glance, and VoiceOver
    /// users get the same glance: how far in, not where every digit is.
    private var accessibilityLabel: String {
        let filled = board.filter { $0 != 0 }.count
        return String(localized: "Sudoku grid, \(filled) of 81 cells filled")
    }
}
