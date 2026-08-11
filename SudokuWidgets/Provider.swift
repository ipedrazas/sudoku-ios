import Foundation
import SudokuKit
import WidgetKit

/// One rendering of a widget: a status, at an instant.
struct DailyEntry: TimelineEntry, Equatable {
    let date: Date
    let status: DailyStatus

    /// Whether the app has ever published anything. Distinguishes "you have not
    /// played yet" from "there is nothing installed here", which want different
    /// words on screen.
    var hasData = true
}

/// Reads the App Group snapshot and nothing else.
///
/// No SwiftData, no generation, no network — a widget refresh has a few seconds
/// and about 30 MB, and a timeline that carved a puzzle would be spending both
/// on work the app has already done. Everything expensive happened in the app;
/// this is a file read and a date comparison.
struct SnapshotProvider: TimelineProvider {

    private let store: SnapshotStore

    init(store: SnapshotStore = .shared) {
        self.store = store
    }

    /// The widget gallery and the moment before the first real read. Never
    /// empty-looking: a placeholder that says "no data" is how a widget talks
    /// someone out of installing it.
    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: .now, status: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        // In the gallery, show the sample rather than this device's real state:
        // an unplayed day would render an empty grid and sell nothing.
        guard !context.isPreview else {
            completion(DailyEntry(date: .now, status: .preview))
            return
        }
        completion(entry(at: .now))
    }

    /// Two entries: now, and the coming UTC midnight.
    ///
    /// The second one is the whole reason this is a timeline rather than a
    /// static view. At midnight there is a new puzzle and the streak goes on the
    /// clock, and no process is running to notice — so the entry is computed
    /// ahead of time from the same snapshot, projected forward by `rolled(to:)`.
    /// The app also reloads timelines whenever it publishes, so this is the
    /// fallback path rather than the usual one.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        let now = Date.now
        let rollover = DailyStatus.nextRollover(after: now)

        let timeline = Timeline(
            entries: [entry(at: now), entry(at: rollover)],
            // Ask again once the day has turned. `.atEnd` rather than a fixed
            // interval: nothing else about a daily changes on a schedule.
            policy: .atEnd
        )
        completion(timeline)
    }

    private func entry(at date: Date) -> DailyEntry {
        guard let status = store.read() else {
            return DailyEntry(date: date, status: .empty(on: date), hasData: false)
        }
        return DailyEntry(date: date, status: status.rolled(to: date))
    }
}

extension DailyStatus {

    /// The sample the gallery shows: a day in progress, mid-streak. Chosen
    /// because it is the state with the most to say — a partly filled grid, a
    /// number of cells left, and a streak worth protecting.
    static var preview: DailyStatus {
        DailyStatus(
            dateKey: DailyPuzzle.dateKey(for: .now),
            isInProgress: true,
            // Counted from the grid below rather than stated, so the number and
            // the picture cannot disagree in a screenshot.
            remainingCells: previewBoard.filter { $0 == "0" }.count,
            elapsedSeconds: 434,
            streak: 12,
            bestStreak: 24,
            lastCompletedDateKey: DailyPuzzle.dateKey(for: Date.now.addingTimeInterval(-86_400)),
            givens: Self.previewGivens,
            board: Self.previewBoard
        )
    }

    /// A real medium puzzle, carried as a literal rather than generated: a
    /// preview must render instantly and identically every time, and calling the
    /// carver from a gallery snapshot is the one place where an 8 ms budget is
    /// genuinely tight.
    private static let previewGivens =
        "530070000600195000098000060800060003400803001700020006060000280000419005000080079"

    private static let previewBoard =
        "534070000672195000198000060800060003400803001700020006060000280000419005000080079"
}
