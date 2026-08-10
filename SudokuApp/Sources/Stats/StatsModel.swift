import Foundation
import SudokuKit

/// One achievement, with whether and when it was earned.
struct AchievementState: Identifiable, Equatable, Sendable {
    let achievement: Achievement
    let unlockedAt: Date?

    var id: String { achievement.key }
    var isUnlocked: Bool { unlockedAt != nil }
}

/// Chart rows. Value types rather than tuples because a chart needs a stable
/// identity per mark, and Swift has no key path into a tuple element.
struct DifficultyCount: Identifiable, Equatable, Sendable {
    let difficulty: Difficulty
    let solved: Int
    var id: String { difficulty.rawValue }
}

struct WeekdayCount: Identifiable, Equatable, Sendable {
    /// 0…6 from the locale's first weekday, which is the x position.
    let index: Int
    let symbol: String
    let solved: Int
    var id: Int { index }
}

struct MonthCount: Identifiable, Equatable, Sendable {
    /// `"YYYY-MM"`.
    let key: String
    let label: String
    let solved: Int
    var id: String { key }
}

struct DifficultyTimes: Identifiable, Equatable, Sendable {
    let difficulty: Difficulty
    let stats: DifficultyTimeStats
    var id: String { difficulty.rawValue }
}

/// One day in the contribution heatmap.
struct ContributionDay: Identifiable, Equatable, Sendable {
    let dateKey: String
    let date: Date
    let solved: Int

    var id: String { dateKey }

    /// 0…4. Zero is "nothing", and the rest are a sequential ramp — the only
    /// place in the stats screen where colour carries magnitude rather than
    /// bar length.
    var level: Int {
        switch solved {
        case 0: 0
        case 1: 1
        case 2: 2
        case 3: 3
        default: 4
        }
    }
}

/// One column of the heatmap: seven days, starting on the locale's first weekday.
struct ContributionWeek: Identifiable, Equatable, Sendable {
    let id: Int
    /// Nil where the week runs past either end of the window.
    let days: [ContributionDay?]
}

/// Everything the stats screen shows, derived from stored rows.
///
/// The aggregation itself lives in `SudokuKit.StatsAggregator` — a port of the
/// six SQL queries the web app used. This is the seam between it and the store:
/// it fetches, aggregates, and answers the two questions the engine cannot,
/// because they are about rows rather than about play.
@Observable
@MainActor
final class StatsModel {

    private(set) var stats: Stats
    private(set) var achievements: [AchievementState] = []
    /// Games started and not finished — what the local completion rate is
    /// measured against.
    private(set) var gamesInProgress = 0
    private(set) var weeks: [ContributionWeek] = []

    private let repository: any GameRepository
    private let calendar: Calendar

    init(repository: any GameRepository, now: Date = Date()) {
        self.repository = repository

        var calendar = DailyPuzzle.calendar
        calendar.firstWeekday = Calendar.current.firstWeekday
        calendar.locale = .current
        self.calendar = calendar

        self.stats = StatsAggregator.aggregate([], now: now)
        refresh(now: now)
    }

    func refresh(now: Date = Date()) {
        let completions = (try? repository.completionRecords()) ?? []
        stats = StatsAggregator.aggregate(completions, now: now)

        let unlocks = (try? repository.achievementUnlocks()) ?? [:]
        achievements = Achievements.all.map {
            AchievementState(achievement: $0, unlockedAt: unlocks[$0.key])
        }

        gamesInProgress = ((try? repository.savedGames()) ?? []).count
        weeks = Self.contributionWeeks(from: stats.byDay, now: now, calendar: calendar)
    }

    // MARK: - Derived

    var hasHistory: Bool { stats.totalFinished > 0 }

    var unlockedCount: Int { achievements.count(where: \.isUnlocked) }

    /// Finished, as a share of everything started that is still accounted for.
    ///
    /// **Not the web app's completion rate, and it cannot be.** That one divided
    /// by every game ever started, which a server could count because it saw
    /// them all. Here a game the player abandons without saving leaves no trace
    /// at all — deliberately, so tapping a difficulty and walking away stores
    /// nothing (§ Phase 4). What is knowable locally is finished versus still
    /// open, so that is what this is, and the screen labels it that way rather
    /// than borrowing a name for a number it is not.
    var completionRate: Double? {
        let total = stats.totalFinished + gamesInProgress
        guard total > 0 else { return nil }
        return Double(stats.totalFinished) / Double(total)
    }

    /// Difficulty counts in ladder order, so the axis reads easy → expert
    /// however sparse the history is.
    var countsByDifficulty: [DifficultyCount] {
        Difficulty.allCases.map { DifficultyCount(difficulty: $0, solved: stats.byDifficulty[$0] ?? 0) }
    }

    /// Weekday counts, rotated to start on the locale's first weekday.
    var countsByWeekday: [WeekdayCount] {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let offset = calendar.firstWeekday - 1

        return (0..<7).map { index in
            // `byDayOfWeek` is keyed 0 = Sunday, matching the web app.
            let day = (index + offset) % 7
            return WeekdayCount(index: index, symbol: symbols[day], solved: stats.byDayOfWeek[day] ?? 0)
        }
    }

    /// The trailing twelve months, including the empty ones.
    ///
    /// Months with no games are the point: a gap that is drawn is information,
    /// and a gap that is skipped silently rewrites the history as unbroken.
    func countsByMonth(now: Date = Date()) -> [MonthCount] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("LLLLL")

        guard let start = calendar.date(byAdding: .month, value: -11, to: now) else { return [] }
        return (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
            let parts = calendar.dateComponents([.year, .month], from: month)
            let key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
            return MonthCount(key: key, label: formatter.string(from: month), solved: stats.byMonth[key] ?? 0)
        }
    }

    var timeStatsByDifficulty: [DifficultyTimes] {
        Difficulty.allCases.compactMap { difficulty in
            stats.timeStats[difficulty].map { DifficultyTimes(difficulty: difficulty, stats: $0) }
        }
    }

    // MARK: - Heatmap

    /// A year of days, in week columns, ending on the week containing `now`.
    ///
    /// Built here rather than in the view so it can be tested without one, and
    /// so the view has nothing to do but colour squares.
    static func contributionWeeks(
        from byDay: [String: Int],
        now: Date,
        calendar: Calendar,
        weeks weekCount: Int = 53
    ) -> [ContributionWeek] {
        let today = calendar.startOfDay(for: now)

        // Back up to the start of this week, then back `weekCount - 1` weeks.
        let weekdayOffset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        guard
            let thisWeekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today),
            let start = calendar.date(byAdding: .day, value: -7 * (weekCount - 1), to: thisWeekStart)
        else { return [] }

        return (0..<weekCount).map { week in
            let days: [ContributionDay?] = (0..<7).map { weekday in
                guard
                    let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start),
                    date <= today
                else { return nil }

                let key = DailyPuzzle.dateKey(for: date)
                return ContributionDay(dateKey: key, date: date, solved: byDay[key] ?? 0)
            }
            return ContributionWeek(id: week, days: days)
        }
    }
}
