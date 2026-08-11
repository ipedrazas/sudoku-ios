import SudokuKit
import SwiftUI

/// Type a puzzle in from a newspaper, and find out what it is before playing it.
struct ImportScreen: View {
    @Bindable var model: ImportModel
    var onPlay: (GeneratedPuzzle) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ImportGrid(model: model)
                    .frame(maxWidth: 480)

                status

                ImportKeypad(model: model)
                    .frame(maxWidth: 480)

                Button {
                    if let puzzle = model.generatedPuzzle() { onPlay(puzzle) }
                } label: {
                    Label("Play this puzzle", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.status.isReady)
                .frame(maxWidth: 480)
                .accessibilityIdentifier("import.play")
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Import a puzzle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        if let text = UIPasteboard.general.string { model.paste(text) }
                    }
                    Button("Clear", systemImage: "trash", role: .destructive) { model.clear() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("import.menu")
            }
        }
    }

    /// Says what is wrong, or what the puzzle turned out to be.
    ///
    /// Always present and never a dead end: every state names the next move
    /// rather than only the problem.
    private var status: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 480)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("import.status")
    }

    private var headline: String {
        switch model.status {
        case .tooFewClues(let clues): "\(clues) of \(ImportModel.minimumClues) clues"
        case .breaksRules: "A digit repeats"
        case .unsolvable: "No solution"
        case .notUnique: "More than one solution"
        case .ready(let tier, let clues): "\(ImportModel.difficulty(for: tier).name) · \(clues) clues"
        }
    }

    private var detail: String {
        switch model.status {
        case .tooFewClues:
            "No Sudoku with a single solution has fewer than 17 clues, so keep going."
        case .breaksRules:
            "Two cells in the same row, column or box hold the same digit. The clashing cells are marked."
        case .unsolvable:
            "These clues are legal but nothing completes them. Check for a mistyped digit."
        case .notUnique:
            "More than one grid fits these clues, so there is no single right answer. Add another clue."
        case .ready(let tier, _):
            ImportModel.describe(tier)
        }
    }

    private var symbol: String {
        switch model.status {
        case .ready: "checkmark.circle.fill"
        case .tooFewClues: "square.and.pencil"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch model.status {
        case .ready: .green
        case .tooFewClues: .secondary
        default: .orange
        }
    }
}

// MARK: - Grid

/// The entry grid. Deliberately not `BoardView`: that one is bound to a
/// `GameSession`, and an import has no session to bind to — it is not a game
/// until it is a puzzle.
private struct ImportGrid: View {
    @Bindable var model: ImportModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<SudokuKit.Grid.size, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<SudokuKit.Grid.size, id: \.self) { column in
                        cell(CellRef(row: row, col: column))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(boxLines)
    }

    private func cell(_ cell: CellRef) -> some View {
        let value = model.grid[cell]
        let isSelected = model.selection == cell
        let isConflict = model.conflicts.contains(cell)

        return ZStack {
            if isSelected {
                Color.accentColor.opacity(0.22)
            } else if isConflict {
                Color.red.opacity(0.16)
            }
            Text(value == 0 ? " " : String(value))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(isConflict ? .red : .primary)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
        .overlay(Rectangle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(.rect)
        .onTapGesture { model.select(cell) }
        .accessibilityElement()
        .accessibilityIdentifier("import.cell.\(cell.index)")
        .accessibilityLabel(
            "Row \(cell.row + 1), column \(cell.col + 1), \(value == 0 ? "empty" : String(value))"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
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
            .stroke(Color.primary.opacity(0.55), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Keypad

private struct ImportKeypad: View {
    @Bindable var model: ImportModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...9, id: \.self) { digit in
                Button {
                    model.input(digit)
                } label: {
                    Text(String(digit))
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.selection == nil)
                .accessibilityIdentifier("import.digit.\(digit)")
            }

            Button {
                model.erase()
            } label: {
                Image(systemName: "delete.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(model.selection == nil)
            .accessibilityIdentifier("import.erase")
            .accessibilityLabel("Erase")
        }
    }
}
