import SudokuKit
import SwiftUI

/// The 1–9 pad plus erase.
///
/// Each key carries how many of that digit are still to place. The web app dims
/// a key once all nine are down (`NumberPad.tsx:18`); a running count is the
/// same information a move earlier, and it is what every competitive Sudoku app
/// shows.
struct NumberPad: View {
    @Bindable var session: GameSession

    var body: some View {
        let remaining = session.remainingCounts

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...SudokuKit.Grid.size, id: \.self) { digit in
                    key(digit, remaining: remaining[digit] ?? 0)
                }
            }

            Button(role: .destructive) {
                session.erase()
            } label: {
                Label("Erase", systemImage: "delete.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(session.selection == nil)
        }
    }

    private func key(_ digit: Int, remaining: Int) -> some View {
        Button {
            session.input(digit)
        } label: {
            VStack(spacing: 1) {
                Text(String(digit))
                    .font(.system(.title2, design: .rounded, weight: .medium))
                Text(remaining > 0 ? String(remaining) : " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        // A digit with none left to place is still tappable — the player may be
        // erasing a wrong one — but it should not invite a tap.
        .opacity(remaining == 0 ? 0.4 : 1)
        .accessibilityLabel(remaining == 0 ? "\(digit), all placed" : "\(digit), \(remaining) remaining")
        .accessibilityIdentifier("digit.\(digit)")
    }
}
