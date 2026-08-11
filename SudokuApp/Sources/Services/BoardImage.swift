import SudokuKit
import SwiftUI

// MARK: - Share as image

/// The board as a picture, for the places a link cannot go.
///
/// Rendered from a view rather than drawn by hand, so it cannot drift from what
/// the app looks like — and rendered at 3× so it survives being sent through
/// something that scales it.
@MainActor
enum BoardImage {
    static func render(_ puzzle: borrowing SudokuKit.Grid, difficulty: Difficulty) -> Image? {
        let renderer = ImageRenderer(content: SharePoster(grid: copy(puzzle), difficulty: difficulty))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }

    /// `borrowing` cannot escape into a view, so the grid is copied once here
    /// rather than the whole call chain giving up the borrow.
    private static func copy(_ grid: borrowing SudokuKit.Grid) -> SudokuKit.Grid {
        SudokuKit.Grid(digits: grid.digits()) ?? SudokuKit.Grid()
    }
}

/// What gets rendered: the grid, its difficulty, and where it came from.
private struct SharePoster: View {
    let grid: SudokuKit.Grid
    let difficulty: Difficulty

    var body: some View {
        VStack(spacing: 12) {
            Text("Sudoku and Cake")
                .font(.headline)
            Text(difficulty.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(0..<SudokuKit.Grid.size, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<SudokuKit.Grid.size, id: \.self) { column in
                            let value = grid[row, column]
                            Text(value == 0 ? " " : String(value))
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .frame(width: 32, height: 32)
                                .overlay(Rectangle().stroke(.black.opacity(0.25), lineWidth: 0.5))
                        }
                    }
                }
            }
            .overlay(boxLines)
        }
        .padding(20)
        // An explicit light ground: the render has no window to inherit a colour
        // scheme from, and a transparent PNG lands on whatever the recipient's
        // app happens to be, which is often black text on black.
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    /// The 3×3 boundaries.
    ///
    /// The vertical step comes from the height and the horizontal from the
    /// width, rather than both from the width. They are equal on a square grid
    /// and only equal there — measured before the square is imposed, a
    /// width-derived vertical step drew the heavy lines across the middle of
    /// rows, which is how this shipped for exactly one screenshot.
    private var boxLines: some View {
        GeometryReader { proxy in
            let columnStep = proxy.size.width / 3
            let rowStep = proxy.size.height / 3
            Path { path in
                for index in 0...3 {
                    path.move(to: CGPoint(x: columnStep * CGFloat(index), y: 0))
                    path.addLine(to: CGPoint(x: columnStep * CGFloat(index), y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: rowStep * CGFloat(index)))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: rowStep * CGFloat(index)))
                }
            }
            .stroke(.black.opacity(0.7), lineWidth: 1.5)
        }
    }
}
