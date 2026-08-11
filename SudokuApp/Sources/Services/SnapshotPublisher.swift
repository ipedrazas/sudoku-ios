import Foundation
import SudokuKit
import WidgetKit

/// Keeps the App Group snapshot in step with the store, and tells WidgetKit.
///
/// The one place that knows how to turn what the app has into what a widget may
/// see. It reads the repository and writes a `DailyStatus`; it never reads the
/// snapshot back, and nothing in the app reads it either — the file is an
/// outbound projection, not shared state, and treating it as shared state is how
/// two sources of truth start.
@MainActor
struct SnapshotPublisher {

    private let repository: any GameRepository
    private let store: SnapshotStore

    init(repository: any GameRepository, store: SnapshotStore = .shared) {
        self.repository = repository
        self.store = store
    }

    /// Builds the current status and writes it.
    ///
    /// Called wherever the app already refreshes its own screens — launch, a
    /// game ending, going to the background, erasing everything. Cheap enough
    /// (a handful of rows and a 300-byte write) that calling it too often is not
    /// a problem worth designing around, and calling it too rarely shows up as a
    /// widget that lies.
    @discardableResult
    func publish(now: Date = Date()) -> DailyStatus {
        let status = status(now: now)
        if store.write(status) {
            // Only when something was actually written. Asking WidgetKit to
            // reload timelines it will rebuild from an unchanged file is work
            // the system budgets, and budget spent on nothing is budget not
            // available at midnight.
            WidgetCenter.shared.reloadAllTimelines()
        }
        return status
    }

    /// The status as the store sees it. Separated from the write so it can be
    /// asserted on directly, without an App Group container in the test bundle.
    func status(now: Date = Date()) -> DailyStatus {
        let dateKey = DailyPuzzle.dateKey(for: now)
        let completions = (try? repository.completions()) ?? []
        let streak = Streak.compute(completions: completions.map(\.completedAt), now: now)

        var status = DailyStatus(
            dateKey: dateKey,
            streak: streak.current,
            bestStreak: streak.best,
            lastCompletedDateKey: completions.map(\.completedAt).max().map(DailyPuzzle.dateKey(for:)),
            updatedAt: now
        )

        // No stored puzzle for today means the daily has not been generated yet,
        // and generating one here is not this type's job: the puzzle row is
        // written by `GameLibrary`, which is the only writer, and a second one
        // would produce two rows for one date key. The widget copes — it says
        // the puzzle is ready, which is true.
        guard let puzzle = try? repository.puzzle(dateKey: dateKey) else { return status }
        status.givens = puzzle.puzzle.digits()

        if let completion = completions.first(where: { $0.puzzleID == puzzle.id }) {
            status.isCompleted = true
            status.elapsedSeconds = completion.timeSeconds
            // The solution, so a finished daily shows a full grid rather than
            // the empty one it was dealt as.
            status.board = puzzle.solution.digits()
            return status
        }

        if let saved = try? repository.savedGame(puzzleID: puzzle.id) {
            status.isInProgress = true
            status.board = saved.board.digits()
            status.remainingCells = saved.board.emptyCells.count
            status.elapsedSeconds = saved.elapsedSeconds
        }

        return status
    }
}
