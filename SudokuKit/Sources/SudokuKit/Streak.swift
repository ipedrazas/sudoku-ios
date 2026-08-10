import Foundation

/// Current and best daily solve streak.
public struct StreakInfo: Equatable, Sendable {
    public let current: Int
    public let best: Int

    public init(current: Int = 0, best: Int = 0) {
        self.current = current
        self.best = best
    }
}

/// Streak computation over completion dates.
///
/// Port of `GetStreakForUser` (`backend/internal/store/store.go:499-564`), where
/// a SQL query did the work. Two details are easy to get wrong and are load
/// bearing, because a streak that silently resets is worse than no streak:
///
/// - A streak counts consecutive **UTC** days, matching the daily's rollover.
/// - The current streak only counts if the most recent completion is **today or
///   yesterday**. Yesterday still counts because a player mid-streak has not yet
///   missed a day — today is not over.
public enum Streak {
    /// Computes the streak from completion timestamps, in any order.
    ///
    /// `now` is injectable so tests are not at the mercy of the wall clock.
    public static func compute(completions: [Date], now: Date = Date()) -> StreakInfo {
        let calendar = DailyPuzzle.calendar

        // Distinct UTC days, newest first — the shape the SQL query returned.
        let days = Set(completions.map { calendar.startOfDay(for: $0) }).sorted(by: >)
        guard let mostRecent = days.first else { return StreakInfo() }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)

        // Current streak: walk back from the newest day until a gap.
        var current = 0
        if mostRecent == today || mostRecent == yesterday {
            current = 1
            for index in 1..<days.count {
                guard isDayBefore(days[index], days[index - 1]) else { break }
                current += 1
            }
        }

        // Best streak: the longest consecutive run anywhere in the history.
        var best = 1
        var run = 1
        for index in 1..<days.count {
            run = isDayBefore(days[index], days[index - 1]) ? run + 1 : 1
            best = max(best, run)
        }

        return StreakInfo(current: current, best: max(best, current))
    }

    /// True when `earlier` is exactly one day before `later`.
    private static func isDayBefore(_ earlier: Date, _ later: Date) -> Bool {
        guard let expected = DailyPuzzle.calendar.date(byAdding: .day, value: -1, to: later) else { return false }
        return earlier == expected
    }
}
