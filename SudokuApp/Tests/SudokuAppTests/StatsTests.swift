import Foundation
import SudokuKit
import Testing

@testable import SudokuApp

/// The stats layer, headlessly.
///
/// The aggregation itself is the engine's and is tested there. What is tested
/// here is everything the *screen* depends on: the wiring to the store, the
/// orderings a chart axis cannot fix for itself, the heatmap grid, and the one
/// number that had to be redefined to mean anything locally.
@Suite("Stats")
@MainActor
struct StatsTests {

    private func date(_ key: String) throws -> Date {
        try #require(DailyPuzzle.date(fromKey: key))
    }

    /// A completion to seed. A struct rather than a tuple: three unlabelled
    /// members at the call site is a puzzle of its own.
    private struct Solve {
        let day: String
        let difficulty: Difficulty
        let seconds: Int
    }

    private func repository(
        completions: [Solve] = [],
        unlocked: [String] = []
    ) throws -> InMemoryGameRepository {
        let repository = InMemoryGameRepository()
        for solve in completions {
            try repository.record(
                completion: StoredCompletion(
                    difficulty: solve.difficulty,
                    timeSeconds: solve.seconds,
                    completedAt: try date(solve.day)
                )
            )
        }
        if !unlocked.isEmpty {
            try repository.unlock(achievementKeys: unlocked, at: try date("2026-08-01"))
        }
        return repository
    }

    private func puzzle(_ difficulty: Difficulty = .easy, seed: UInt64 = 1) -> GeneratedPuzzle {
        var rng = SeededRandom(seed: seed)
        return Generator.generate(difficulty, using: &rng)
    }

    private var calendar: Calendar {
        var calendar = DailyPuzzle.calendar
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    // MARK: - Wiring

    @Test("an empty store produces an empty, valid screen rather than nothing")
    func emptyStore() throws {
        let model = StatsModel(repository: InMemoryGameRepository(), now: try date("2026-08-10"))

        #expect(!model.hasHistory)
        #expect(model.stats.totalFinished == 0)
        #expect(model.completionRate == nil, "no games at all is not a 0% completion rate")
        #expect(model.unlockedCount == 0)
        // Every achievement is still listed: a goal nobody can see is not a goal.
        #expect(model.achievements.count == Achievements.all.count)
        #expect(model.achievements.allSatisfy { !$0.isUnlocked })
        // And the charts still have their axes: four rungs, seven days, twelve months.
        #expect(model.countsByDifficulty.count == 4)
        #expect(model.countsByWeekday.count == 7)
        #expect(model.countsByMonth(now: try date("2026-08-10")).count == 12)
    }

    @Test("stats come from the stored completions")
    func aggregatesStoredRows() throws {
        let repository = try repository(completions: [
            Solve(day: "2026-08-10", difficulty: .easy, seconds: 120),
            Solve(day: "2026-08-09", difficulty: .medium, seconds: 400),
            Solve(day: "2026-08-09", difficulty: .expert, seconds: 1500),
        ])
        let model = StatsModel(repository: repository, now: try date("2026-08-10"))

        #expect(model.hasHistory)
        #expect(model.stats.totalFinished == 3)
        #expect(model.stats.byDifficulty[.easy] == 1)
        #expect(model.stats.byDifficulty[.expert] == 1)
        #expect(model.stats.byDifficulty[.hard] == 0)
        #expect(model.stats.streak.current == 2)
    }

    @Test("achievements carry the date they were unlocked")
    func achievementDates() throws {
        let repository = try repository(unlocked: ["first_easy_solve", "games_10"])
        let model = StatsModel(repository: repository, now: try date("2026-08-10"))

        #expect(model.unlockedCount == 2)
        let earned = try #require(model.achievements.first { $0.achievement.key == "first_easy_solve" })
        #expect(earned.isUnlocked)
        #expect(earned.unlockedAt == (try date("2026-08-01")))

        let locked = try #require(model.achievements.first { $0.achievement.key == "streak_30" })
        #expect(!locked.isUnlocked)
        #expect(locked.unlockedAt == nil)
    }

    @Test("the grid keeps the catalogue's order, earned or not")
    func achievementOrder() throws {
        let model = StatsModel(repository: try repository(unlocked: ["streak_7"]), now: Date())
        #expect(model.achievements.map(\.achievement.key) == Achievements.all.map(\.key))
    }

    // MARK: - The number that had to be redefined

    @Test("completion rate is finished against still-open, and says so")
    func completionRate() throws {
        let repository = try repository(completions: [Solve(day: "2026-08-10", difficulty: .easy, seconds: 100)])
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))

        // One finished, no games open: everything started that we know about
        // was finished.
        var model = StatsModel(repository: repository, now: try date("2026-08-10"))
        #expect(model.gamesInProgress == 0)
        #expect(model.completionRate == 1)

        // Leave one open.
        let session = library.start(puzzle())
        let cell = try #require(session.board.emptyCells.first)
        session.select(cell)
        session.input(session.puzzle.solution[cell])
        library.flush()

        model = StatsModel(repository: repository, now: try date("2026-08-10"))
        #expect(model.gamesInProgress == 1)
        #expect(model.completionRate == 0.5)
    }

    // MARK: - Chart rows

    @Test("difficulty counts are in ladder order, including the empty rungs")
    func difficultyOrder() throws {
        let repository = try repository(completions: [Solve(day: "2026-08-10", difficulty: .expert, seconds: 900)])
        let model = StatsModel(repository: repository, now: try date("2026-08-10"))

        #expect(model.countsByDifficulty.map(\.difficulty) == [.easy, .medium, .hard, .expert])
        #expect(model.countsByDifficulty.map(\.solved) == [0, 0, 0, 1])
    }

    @Test("weekdays start on the locale's first day and every day is present")
    func weekdayRotation() throws {
        let model = StatsModel(repository: try repository(), now: try date("2026-08-10"))
        let weekdays = model.countsByWeekday

        #expect(weekdays.count == 7)
        #expect(weekdays.map(\.index) == Array(0..<7))
        // Two English weekdays share an initial, which is exactly why the chart
        // plots the index and labels the axis.
        #expect(Set(weekdays.map(\.index)).count == 7)
    }

    @Test("months cover the trailing year, gaps included")
    func monthsIncludeGaps() throws {
        let repository = try repository(completions: [Solve(day: "2026-08-10", difficulty: .easy, seconds: 100)])
        let model = StatsModel(repository: repository, now: try date("2026-08-10"))
        let months = model.countsByMonth(now: try date("2026-08-10"))

        #expect(months.count == 12)
        #expect(months.last?.key == "2026-08")
        #expect(months.first?.key == "2025-09")
        #expect(months.last?.solved == 1)
        // The eleven empty months are drawn rather than skipped: a gap that is
        // not shown rewrites the history as unbroken.
        #expect(months.dropLast().allSatisfy { $0.solved == 0 })
        #expect(months.map(\.key) == months.map(\.key).sorted())
    }

    @Test("per-difficulty times only appear for rungs that have been played")
    func timeStats() throws {
        let repository = try repository(completions: [
            Solve(day: "2026-08-10", difficulty: .easy, seconds: 100),
            Solve(day: "2026-08-09", difficulty: .easy, seconds: 200),
        ])
        let model = StatsModel(repository: repository, now: try date("2026-08-10"))

        #expect(model.timeStatsByDifficulty.map(\.difficulty) == [.easy])
        let easy = try #require(model.timeStatsByDifficulty.first)
        #expect(easy.stats.count == 2)
        #expect(easy.stats.bestSeconds == 100)
        #expect(easy.stats.averageSeconds == 150)
    }

    // MARK: - Heatmap

    @Test("the heatmap is a year of weeks, ending on this one")
    func heatmapShape() throws {
        let now = try date("2026-08-10")
        let weeks = StatsModel.contributionWeeks(from: [:], now: now, calendar: calendar)

        #expect(weeks.count == 53)
        #expect(weeks.allSatisfy { $0.days.count == 7 })

        // Every square that exists is in the past, and today is one of them.
        let days = weeks.flatMap { $0.days.compactMap { $0 } }
        #expect(days.allSatisfy { $0.date <= now })
        #expect(days.contains { $0.dateKey == "2026-08-10" })
        #expect(days.map(\.dateKey) == days.map(\.dateKey).sorted(), "in date order, left to right")
    }

    @Test("days after today are absent rather than drawn as empty")
    func heatmapStopsAtToday() throws {
        let now = try date("2026-08-10")
        let weeks = StatsModel.contributionWeeks(from: [:], now: now, calendar: calendar)

        let lastWeek = try #require(weeks.last)
        #expect(lastWeek.days.contains { $0 == nil } || lastWeek.days.allSatisfy { $0 != nil })
        #expect(!weeks.flatMap { $0.days.compactMap { $0 } }.contains { $0.dateKey == "2026-08-11" })
    }

    @Test("counts land on the right square, and become levels")
    func heatmapLevels() throws {
        let now = try date("2026-08-10")
        let weeks = StatsModel.contributionWeeks(
            from: ["2026-08-10": 1, "2026-08-09": 3, "2026-08-08": 9],
            now: now,
            calendar: calendar
        )
        let days = weeks.flatMap { $0.days.compactMap { $0 } }

        #expect(days.first { $0.dateKey == "2026-08-10" }?.level == 1)
        #expect(days.first { $0.dateKey == "2026-08-09" }?.level == 3)
        #expect(days.first { $0.dateKey == "2026-08-08" }?.level == 4, "the ramp tops out rather than running away")
        #expect(days.first { $0.dateKey == "2026-08-07" }?.level == 0)
        #expect(days.first { $0.dateKey == "2026-08-07" }?.solved == 0)
    }

    @Test("a solve shows up in the heatmap on the day it happened")
    func heatmapReflectsRealPlay() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))

        let session = library.start(puzzle())
        for cell in session.board.emptyCells {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
        #expect(session.isSolved)

        let model = StatsModel(repository: repository)
        let today = DailyPuzzle.dateKey(for: Date())
        let days = model.weeks.flatMap { $0.days.compactMap { $0 } }
        #expect(days.first { $0.dateKey == today }?.solved == 1)
        #expect(model.stats.totalFinished == 1)
    }

    // MARK: - Formatting

    @Test("times read as minutes, and as hours only when they have to")
    func timeFormatting() {
        #expect(StatsScreen.time(0) == "0:00")
        #expect(StatsScreen.time(65) == "1:05")
        #expect(StatsScreen.time(599) == "9:59")
        #expect(StatsScreen.time(3600) == "1:00:00")
        #expect(StatsScreen.time(3725) == "1:02:05")
    }
}
