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
        .task {
            provider.warmUp()
            if let difficulty = Self.launchDifficulty { start(difficulty) }
        }
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

    /// Lets a launch argument open straight into a game: `-startGame easy`.
    ///
    /// A development affordance, and a deliberate one. Screenshot and UI-test
    /// runs otherwise have to drive the picker first, which is slow and makes
    /// them fail for reasons that have nothing to do with what they are testing.
    private static var launchDifficulty: Difficulty? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-startGame"), index + 1 < arguments.count else {
            return nil
        }
        return Difficulty(rawValue: arguments[index + 1])
    }

    private func start(_ difficulty: Difficulty) {
        Task {
            let puzzle = await provider.newGame(difficulty)
            let session = GameSession(puzzle: puzzle, showsConflicts: true)
            Self.prefill(session)
            self.session = session
        }
    }

    /// `-prefill N` fills all but N cells from the solution.
    ///
    /// The companion to `-startGame`, and for the same reason: the states worth
    /// looking at hardest — a nearly finished grid, the win card — are the most
    /// tedious to reach by tapping. Screenshots and UI tests use it; nothing
    /// else does.
    private static func prefill(_ session: GameSession) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-prefill"), index + 1 < arguments.count,
            let remaining = Int(arguments[index + 1])
        else { return }

        let empties = session.board.emptyCells
        for cell in empties.dropLast(max(0, remaining)) {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
        session.selection = nil
    }
}
