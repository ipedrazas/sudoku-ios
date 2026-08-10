import SudokuKit
import SwiftUI

/// The tracer bullet: pick a difficulty, get a real generated puzzle, play it.
///
/// Deliberately thin. The real shell — daily, calendar, stats, settings, and a
/// `NavigationSplitView` sidebar on iPad — arrives with the phases that fill
/// those screens. What this proves is the whole vertical slice: the engine
/// generates, the pool serves, the board renders, and a tap places a digit.
struct RootView: View {
    @State private var provider = PuzzleProvider()
    @State private var session: GameSession?

    var body: some View {
        NavigationStack {
            if let session {
                GameScreen(session: session) { self.session = nil }
            } else {
                difficultyPicker
            }
        }
        .task { provider.warmUp() }
    }

    private var difficultyPicker: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Sudoku and Cake")
                    .font(.largeTitle.bold())
                Text("Every puzzle is solvable by logic alone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Button {
                        start(difficulty)
                    } label: {
                        HStack {
                            Text(difficulty.name)
                                .font(.headline)
                            Spacer()
                            Text(hint(for: difficulty))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("difficulty.\(difficulty.rawValue)")
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal)
        }
        .navigationTitle("New game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    /// Names the technique each rung actually requires. The difficulty ladder is
    /// defined by technique rather than clue count, so saying so is more honest
    /// than "medium" and teaches the vocabulary the hints will use.
    private func hint(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .easy: "scanning"
        case .medium: "locked candidates"
        case .hard: "and a little more"
        case .expert: "hidden pairs, X-wings"
        }
    }

    private func start(_ difficulty: Difficulty) {
        Task {
            let puzzle = await provider.newGame(difficulty)
            session = GameSession(puzzle: puzzle)
        }
    }
}
