import Foundation
import SudokuKit

/// One square in the month grid. Blank squares pad the first week.
struct CalendarCell: Identifiable, Hashable, Sendable {
    /// Position in the grid, which is what makes the blanks distinguishable.
    let id: Int
    let date: Date?
    let dateKey: String?
    let dayNumber: Int?

    static func blank(at position: Int) -> CalendarCell {
        CalendarCell(id: position, date: nil, dateKey: nil, dayNumber: nil)
    }
}

/// The daily screen's state: what has been played, the streak, and the month
/// being browsed.
///
/// Read-only over the store. Creating and playing sessions stays in
/// `GameLibrary`; this only answers questions about them.
@Observable
@MainActor
final class DailyModel {

    /// Every daily the store knows about, keyed `"YYYY-MM-DD"`.
    private(set) var states: [String: DailyState] = [:]
    private(set) var streak = StreakInfo()

    /// Any date inside the month the calendar is showing.
    private(set) var visibleMonth: Date

    private let repository: any GameRepository
    /// UTC for day arithmetic — a daily rolls over at the same instant
    /// everywhere — but the *display* takes its first weekday from the user's
    /// locale, because a grid that starts on the wrong day is just wrong.
    private let calendar: Calendar

    init(repository: any GameRepository, now: Date = Date()) {
        self.repository = repository

        var calendar = DailyPuzzle.calendar
        calendar.firstWeekday = Calendar.current.firstWeekday
        calendar.locale = .current
        self.calendar = calendar

        self.visibleMonth = DailyPuzzle.utcMidnight(of: now)
        refresh(now: now)
    }

    // MARK: - State

    func refresh(now: Date = Date()) {
        states = (try? repository.dailyStates()) ?? [:]
        // Every completion counts, not only dailies: this is the same streak the
        // achievements use (`store.GetStreakForUser`), and two numbers both
        // called "streak" that disagree would be worse than either.
        let completions = (try? repository.completions()) ?? []
        streak = Streak.compute(completions: completions.map(\.completedAt), now: now)
    }

    func state(forKey key: String) -> DailyState? { states[key] }

    func todayKey(now: Date = Date()) -> String { DailyPuzzle.dateKey(for: now) }

    func today(now: Date = Date()) -> DailyState? { states[todayKey(now: now)] }

    func isCompleted(now: Date = Date()) -> Bool { today(now: now)?.isCompleted ?? false }

    // MARK: - Month navigation

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: visibleMonth)
    }

    /// Weekday initials, rotated to start on the locale's first weekday.
    var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// The grid for `visibleMonth`: leading blanks, then every day of the month.
    var cells: [CalendarCell] {
        guard
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)),
            let range = calendar.range(of: .day, in: .month, for: start)
        else { return [] }

        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var cells = (0..<leading).map(CalendarCell.blank(at:))
        for (offset, day) in range.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            cells.append(
                CalendarCell(
                    id: leading + offset,
                    date: date,
                    dateKey: DailyPuzzle.dateKey(for: date),
                    dayNumber: day
                )
            )
        }
        return cells
    }

    /// Days ahead of today are not playable — the seed exists, but a daily that
    /// can be played early is not a daily.
    func isPlayable(_ cell: CalendarCell, now: Date = Date()) -> Bool {
        guard let date = cell.date else { return false }
        return date <= DailyPuzzle.utcMidnight(of: now)
    }

    func isToday(_ cell: CalendarCell, now: Date = Date()) -> Bool {
        cell.dateKey == DailyPuzzle.dateKey(for: now)
    }

    func showPreviousMonth() {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: visibleMonth) else { return }
        visibleMonth = previous
    }

    func showNextMonth() {
        guard canShowNextMonth, let next = calendar.date(byAdding: .month, value: 1, to: visibleMonth) else { return }
        visibleMonth = next
    }

    /// There is nothing to see in a future month, so the chevron turns off
    /// rather than paging into empty grids.
    func canShowNextMonth(now: Date = Date()) -> Bool {
        let current = calendar.dateComponents([.year, .month], from: now)
        let visible = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let currentYear = current.year, let currentMonth = current.month,
            let visibleYear = visible.year, let visibleMonth = visible.month
        else { return false }
        return (visibleYear, visibleMonth) < (currentYear, currentMonth)
    }

    var canShowNextMonth: Bool { canShowNextMonth(now: Date()) }

    func showMonth(containing date: Date) {
        visibleMonth = DailyPuzzle.utcMidnight(of: date)
    }
}
