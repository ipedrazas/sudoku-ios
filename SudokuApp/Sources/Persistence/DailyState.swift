import Foundation
import SudokuKit

/// What the store knows about one day's puzzle.
///
/// A daily has three states in the calendar — untouched, started, finished — and
/// they come from three different tables. This is the join, computed once rather
/// than in each view that needs it.
struct DailyState: Equatable, Sendable, Identifiable {
    let dateKey: String
    let puzzleID: UUID
    /// When it was first finished, if it has been.
    let completedAt: Date?
    /// The time that first completion took.
    let timeSeconds: Int?
    /// Set only while a game is in progress.
    let elapsedSeconds: Int?
    /// Cells left to fill, while in progress.
    let remainingCells: Int?

    var id: String { dateKey }
    var isCompleted: Bool { completedAt != nil }
    /// Started but not finished. A finished daily that was later restarted still
    /// reads as completed — the day counts, and it cannot un-count.
    var isInProgress: Bool { completedAt == nil && elapsedSeconds != nil }

    var formattedTime: String? {
        guard let seconds = timeSeconds ?? elapsedSeconds else { return nil }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension GameRepository {

    /// Every daily the store has generated, keyed by date key.
    ///
    /// A default implementation rather than a method on each repository: the
    /// join is the same for both, and writing it twice is how the two drift.
    func dailyStates() throws -> [String: DailyState] {
        let dailies = try dailyPuzzles()
        guard !dailies.isEmpty else { return [:] }

        // Oldest first, so `first(where:)` finds the completion that actually
        // counted — replaying a daily does not move the day it was solved on.
        let completions = try self.completions()
        let saved = try savedGames().reduce(into: [UUID: SavedGameSummary]()) { $0[$1.id] = $1 }

        return dailies.reduce(into: [:]) { result, puzzle in
            guard let dateKey = puzzle.dateKey else { return }
            let completion = completions.first { $0.puzzleID == puzzle.id }
            let inProgress = saved[puzzle.id]

            result[dateKey] = DailyState(
                dateKey: dateKey,
                puzzleID: puzzle.id,
                completedAt: completion?.completedAt,
                timeSeconds: completion?.timeSeconds,
                elapsedSeconds: inProgress?.state.elapsedSeconds,
                remainingCells: inProgress?.remainingCells
            )
        }
    }
}
