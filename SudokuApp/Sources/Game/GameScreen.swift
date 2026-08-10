import SudokuKit
import SwiftUI

/// One puzzle, board above and controls below.
///
/// The layout is the compact-width arrangement from §8.1 of the plan: board near
/// the top, controls in the bottom third where a thumb can reach them. The
/// regular-width split for iPad, both input orders, and the full control bar are
/// Phase 3 (P3-3, P3-4, P3-10).
struct GameScreen: View {
    @Bindable var session: GameSession
    var onNewGame: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            BoardView(session: session)
                .padding(.horizontal, 8)

            if session.isSolved {
                Label("Solved", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            NumberPad(session: session)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .animation(.snappy, value: session.isSolved)
        .navigationTitle(session.difficulty.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("New", systemImage: "plus", action: onNewGame)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Restart", systemImage: "arrow.counterclockwise") {
                    session.restart()
                }
            }
        }
    }
}
