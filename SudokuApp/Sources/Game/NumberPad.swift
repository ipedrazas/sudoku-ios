import SudokuKit
import SwiftUI

/// The 1–9 pad.
///
/// Each key carries how many of that digit are still to place. The web app dims
/// a key once all nine are down (`NumberPad.tsx:18`); a running count is the
/// same information a move earlier, and it is what every competitive Sudoku app
/// shows.
struct NumberPad: View {
    /// How the nine keys are arranged.
    enum Layout {
        /// One row of nine — the full width of a phone.
        case row
        /// Three by three. In a side column on iPad a single row would give each
        /// key about 30 points, which is below the minimum touch target; the
        /// grid also echoes the shape of a Sudoku box.
        case grid
    }

    @Bindable var session: GameSession
    var layout: Layout = .row

    /// Same 450 ms as the board's long-press, for a one-shot note without
    /// leaving normal mode.
    private static let longPressDuration = 0.45

    var body: some View {
        let remaining = session.remainingCounts

        switch layout {
        case .row:
            HStack(spacing: 5) {
                ForEach(1...SudokuKit.Grid.size, id: \.self) { digit in
                    key(digit, remaining: remaining[digit] ?? 0)
                }
            }
        case .grid:
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { column in
                            let digit = row * 3 + column
                            key(digit, remaining: remaining[digit] ?? 0)
                        }
                    }
                }
            }
        }
    }

    private func key(_ digit: Int, remaining: Int) -> some View {
        let isArmed = session.armedDigit == digit
        let isDone = remaining == 0

        return Button {
            session.input(digit)
        } label: {
            VStack(spacing: 0) {
                Text(String(digit))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text(isDone ? " " : String(remaining))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, layout == .grid ? 18 : 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isArmed ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isArmed ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A digit with none left to place stays tappable — the player may be
        // erasing a wrong one — but it should not invite a tap.
        .opacity(isDone ? 0.4 : 1)
        .onLongPressGesture(minimumDuration: Self.longPressDuration) {
            session.inputNote(digit)
        }
        .accessibilityIdentifier("digit.\(digit)")
        .accessibilityLabel(isDone ? "\(digit), all placed" : "\(digit), \(remaining) remaining")
        .accessibilityHint("Double tap and hold to add a note")
    }
}
