import Foundation
import SudokuKit

/// Everything a widget is allowed to know, in one value.
///
/// This file is compiled into **both** the app and the widget extension. It is
/// the entire contract between the two processes: the app writes one of these
/// into the App Group container and the widget reads it. The widget never opens
/// the SwiftData store — two processes over one store is a locking problem, a
/// migration problem, and a "widget crashed the day the schema changed" problem,
/// and none of that buys anything a 300-byte JSON file does not.
///
/// Every field is either non-optional with a default or optional, so a file
/// written by a newer build still decodes in an older reader. Unknown keys are
/// ignored by `JSONDecoder`, which is the behaviour we want: an update that adds
/// a field must not blank the widget of whoever has not relaunched yet.
struct DailyStatus: Codable, Equatable, Sendable {

    /// The UTC day this describes. Compared against the reader's idea of today,
    /// which is what makes a stale snapshot detectable rather than misleading.
    var dateKey: String

    /// Today's daily has been solved.
    var isCompleted: Bool = false

    /// Started, not finished.
    var isInProgress: Bool = false

    /// Cells still to fill, while in progress.
    var remainingCells: Int?

    /// Seconds on the clock, while in progress.
    var elapsedSeconds: Int?

    var streak: Int = 0
    var bestStreak: Int = 0

    /// The day of the most recent completion of anything, which is what decides
    /// whether `streak` is still alive. Without it a snapshot from four days ago
    /// would show a 12-day streak that ended three days ago — the one number a
    /// streak widget must never get wrong.
    var lastCompletedDateKey: String?

    /// Today's puzzle as dealt: 81 digits, `0` for empty. Nil until the daily has
    /// actually been generated and stored.
    var givens: String?

    /// The board as the player left it, same encoding. Nil when untouched, in
    /// which case the givens *are* the board.
    var board: String?

    var updatedAt: Date = Date()

    init(
        dateKey: String,
        isCompleted: Bool = false,
        isInProgress: Bool = false,
        remainingCells: Int? = nil,
        elapsedSeconds: Int? = nil,
        streak: Int = 0,
        bestStreak: Int = 0,
        lastCompletedDateKey: String? = nil,
        givens: String? = nil,
        board: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.dateKey = dateKey
        self.isCompleted = isCompleted
        self.isInProgress = isInProgress
        self.remainingCells = remainingCells
        self.elapsedSeconds = elapsedSeconds
        self.streak = streak
        self.bestStreak = bestStreak
        self.lastCompletedDateKey = lastCompletedDateKey
        self.givens = givens
        self.board = board
        self.updatedAt = updatedAt
    }

    /// What a widget should show: untouched, in progress, or done.
    enum Standing: Equatable, Sendable {
        case ready
        case inProgress
        case completed
    }

    var standing: Standing {
        if isCompleted { return .completed }
        return isInProgress ? .inProgress : .ready
    }

    /// The board to draw: what the player has done, or the puzzle as dealt.
    var displayBoard: String? { board ?? givens }

    // MARK: - Staleness

    /// This snapshot as it stands at `date`.
    ///
    /// A widget's timeline outlives the app run that wrote it. At the next UTC
    /// midnight yesterday's snapshot stops being true in two ways at once —
    /// there is a new puzzle, and the streak is on the clock — and the widget
    /// process has no way to be told. So rather than trusting the file, every
    /// read is projected forward to the moment being rendered.
    ///
    /// Rolling forward is deliberately lossy: everything about *yesterday's*
    /// board is dropped, because a widget showing yesterday's half-finished grid
    /// under today's date is worse than one showing nothing.
    ///
    /// The streak survives one day of grace, exactly as `Streak.compute` does —
    /// a player mid-streak who has not opened the app yet today has not missed a
    /// day. Two days of silence and it is gone, and the widget says so without
    /// being told.
    func rolled(to date: Date) -> DailyStatus {
        let today = DailyPuzzle.dateKey(for: date)
        var status = self
        status.streak = Self.isStreakAlive(lastCompletedDateKey, on: date) ? streak : 0

        guard dateKey != today else { return status }

        status.dateKey = today
        status.isCompleted = false
        status.isInProgress = false
        status.remainingCells = nil
        status.elapsedSeconds = nil
        status.givens = nil
        status.board = nil
        return status
    }

    /// A streak counts while its last completion is today or yesterday, in UTC.
    static func isStreakAlive(_ lastCompletedDateKey: String?, on date: Date) -> Bool {
        guard let key = lastCompletedDateKey, let last = DailyPuzzle.date(fromKey: key) else { return false }
        let today = DailyPuzzle.utcMidnight(of: date)
        guard let yesterday = DailyPuzzle.calendar.date(byAdding: .day, value: -1, to: today) else { return false }
        return last >= yesterday
    }

    /// The next instant at which any of this changes on its own: the coming UTC
    /// midnight. What the widget's timeline schedules its refresh for.
    static func nextRollover(after date: Date) -> Date {
        let today = utcMidnight(of: date)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? date.addingTimeInterval(86_400)
    }

    private static var calendar: Calendar { DailyPuzzle.calendar }
    private static func utcMidnight(of date: Date) -> Date { DailyPuzzle.utcMidnight(of: date) }

    /// A status for a day nothing is known about — what the widget shows before
    /// the app has ever run, and what the previews are built from.
    static func empty(on date: Date = Date()) -> DailyStatus {
        DailyStatus(dateKey: DailyPuzzle.dateKey(for: date), updatedAt: date)
    }
}
