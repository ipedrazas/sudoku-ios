import Foundation
import SudokuKit
import Testing

@testable import SudokuApp

/// The daily, the calendar and the reminder.
///
/// The claim Phase 5 has to make good on is that two devices which have never
/// spoken produce the same puzzle for the same day, and that any past day is
/// playable with nothing stored. Both are testable without a device, because
/// both are consequences of the seed rather than of the network.
@Suite("Daily")
@MainActor
struct DailyTests {

    private func library(_ repository: any GameRepository) -> GameLibrary {
        GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))
    }

    /// A fixed date, so nothing here depends on the day the tests run.
    private func date(_ key: String) throws -> Date {
        try #require(DailyPuzzle.date(fromKey: key), "\(key) should parse")
    }

    private func solve(_ session: GameSession) {
        for cell in session.board.emptyCells {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
    }

    // MARK: - Determinism

    @Test("two devices that have never spoken produce the same daily")
    func sameDateSamePuzzleAcrossStores() async throws {
        let day = try date("2026-08-10")

        // Two independent stores — the stand-in for two simulators.
        let first = await library(InMemoryGameRepository()).daily(for: day)
        let second = await library(InMemoryGameRepository()).daily(for: day)

        #expect(first.puzzle.puzzle == second.puzzle.puzzle)
        #expect(first.puzzle.solution == second.puzzle.solution)
        #expect(first.puzzle.difficulty == DailyPuzzle.difficulty)
    }

    @Test("a SwiftData store agrees with an in-memory one")
    func sameDateAcrossRepositoryKinds() async throws {
        let day = try date("2026-03-03")
        let container = try #require(SwiftDataRepository.container(inMemory: true))

        let stored = await library(SwiftDataRepository(container: container)).daily(for: day)
        let memory = await library(InMemoryGameRepository()).daily(for: day)

        #expect(stored.puzzle.puzzle == memory.puzzle.puzzle)
    }

    @Test("different days are different puzzles")
    func differentDatesDiffer() async throws {
        let repository = InMemoryGameRepository()
        let library = library(repository)

        let first = await library.daily(for: try date("2026-08-10"))
        let second = await library.daily(for: try date("2026-08-11"))

        #expect(first.puzzle.puzzle != second.puzzle.puzzle)
        #expect(first.id != second.id)
    }

    // MARK: - Caching

    @Test("the daily is generated once and then cached")
    func dailyIsCached() async throws {
        let repository = InMemoryGameRepository()
        let library = library(repository)
        let day = try date("2026-08-10")

        let first = await library.daily(for: day)
        let second = await library.daily(for: day)

        // A regenerated puzzle would arrive with a new identity, so a stable id
        // is the evidence that the cache was used rather than the generator.
        #expect(first.id == second.id)
        #expect(try repository.dailyPuzzles().count == 1)
        #expect(try repository.puzzle(dateKey: "2026-08-10")?.source == .daily)
    }

    @Test("the cached daily matches what the generator would produce")
    func cacheMatchesGenerator() async throws {
        let repository = InMemoryGameRepository()
        let day = try date("2026-08-10")

        let session = await library(repository).daily(for: day)
        #expect(session.puzzle.puzzle == DailyPuzzle.generate(for: day).puzzle)
    }

    @Test("a daily survives a relaunch as the same puzzle")
    func dailySurvivesRelaunch() async throws {
        let repository = InMemoryGameRepository()
        let day = try date("2026-08-10")

        let first = library(repository)
        let session = await first.daily(for: day)
        let cell = try #require(session.board.emptyCells.first)
        session.select(cell)
        session.input(session.puzzle.solution[cell])
        for _ in 0..<42 { session.tick() }
        first.flush()

        let relaunched = await library(repository).daily(for: day)
        #expect(relaunched.id == session.id)
        #expect(relaunched.board == session.board)
        #expect(relaunched.elapsedSeconds == 42)
    }

    // MARK: - History

    @Test("any past day is playable with nothing stored")
    func pastDaysArePlayable() async throws {
        let repository = InMemoryGameRepository()
        let library = library(repository)

        // A fresh install, reaching back a year.
        for key in ["2025-01-01", "2025-06-15", "2026-02-28"] {
            let session = await library.daily(for: try date(key))
            #expect(session.board == session.puzzle.puzzle)
            #expect(!session.isSolved)
            #expect(try repository.puzzle(dateKey: key) != nil)
        }
    }

    @Test("the calendar knows unplayed from started from solved")
    func dailyStates() async throws {
        let repository = InMemoryGameRepository()
        let library = library(repository)

        // Untouched.
        _ = await library.daily(for: try date("2026-08-08"))

        // Started.
        let started = await library.daily(for: try date("2026-08-09"))
        let cell = try #require(started.board.emptyCells.first)
        started.select(cell)
        started.input(started.puzzle.solution[cell])
        library.flush()

        // Solved.
        let solved = await library.daily(for: try date("2026-08-10"))
        for _ in 0..<120 { solved.tick() }
        solve(solved)

        let states = try repository.dailyStates()
        #expect(states.count == 3)

        let untouched = try #require(states["2026-08-08"])
        #expect(!untouched.isCompleted)
        #expect(!untouched.isInProgress)

        let inProgress = try #require(states["2026-08-09"])
        #expect(inProgress.isInProgress)
        #expect(inProgress.remainingCells == started.board.emptyCells.count)

        let finished = try #require(states["2026-08-10"])
        #expect(finished.isCompleted)
        #expect(finished.timeSeconds == 120)
        #expect(!finished.isInProgress)
    }

    @Test("replaying a solved daily does not un-solve the day")
    func replayKeepsTheDaySolved() async throws {
        let repository = InMemoryGameRepository()
        let library = library(repository)
        let day = try date("2026-08-10")

        let session = await library.daily(for: day)
        solve(session)

        // Come back and start it again.
        let replay = await library.daily(for: day)
        let cell = try #require(replay.board.emptyCells.first)
        replay.select(cell)
        replay.input(replay.puzzle.solution[cell])
        library.flush()

        let state = try #require(try repository.dailyStates()["2026-08-10"])
        #expect(state.isCompleted, "the day was solved and cannot become unsolved")
        #expect(!state.isInProgress)
    }

    @Test("a solved daily is not offered in the resume list")
    func solvedDailyLeavesTheResumeList() async throws {
        let repository = InMemoryGameRepository()
        let library = library(repository)

        let session = await library.daily(for: try date("2026-08-10"))
        let cell = try #require(session.board.emptyCells.first)
        session.select(cell)
        session.input(session.puzzle.solution[cell])
        library.flush()
        #expect(library.savedGames.count == 1)

        solve(session)
        #expect(library.savedGames.isEmpty)
        #expect(try repository.puzzle(dateKey: "2026-08-10") != nil, "but the puzzle stays — it is the day")
    }

    // MARK: - The model

    @Test("the streak comes from the stored completions")
    func streakSurfaces() async throws {
        let repository = InMemoryGameRepository()
        let now = try date("2026-08-10")

        for offset in 0..<3 {
            let day = try #require(DailyPuzzle.calendar.date(byAdding: .day, value: -offset, to: now))
            try repository.record(completion: StoredCompletion(difficulty: .medium, timeSeconds: 300, completedAt: day))
        }

        let model = DailyModel(repository: repository, now: now)
        #expect(model.streak.current == 3)
        #expect(model.streak.best == 3)
    }

    @Test("the month grid is padded to start on the right weekday")
    func monthGrid() throws {
        let repository = InMemoryGameRepository()
        let model = DailyModel(repository: repository, now: try date("2026-08-10"))

        #expect(model.weekdaySymbols.count == 7)

        let cells = model.cells
        let days = cells.compactMap(\.dayNumber)
        #expect(days == Array(1...31), "August has 31 days, in order")

        // The blanks are leading, and there are fewer than a week of them.
        let blanks = cells.prefix { $0.dayNumber == nil }
        #expect(blanks.count < 7)
        #expect(blanks.count + days.count == cells.count)
        #expect(cells.dropFirst(blanks.count).allSatisfy { $0.dayNumber != nil })
    }

    @Test("the calendar does not page into the future")
    func futureMonthsAreClosed() throws {
        let now = try date("2026-08-10")
        let model = DailyModel(repository: InMemoryGameRepository(), now: now)

        #expect(!model.canShowNextMonth(now: now), "already showing the current month")

        model.showPreviousMonth()
        #expect(model.canShowNextMonth(now: now))
        #expect(!model.monthTitle.isEmpty)

        model.showNextMonth()
        #expect(!model.canShowNextMonth(now: now), "and back to the current month")
    }

    @Test("future days are not playable, today is")
    func futureDaysAreNotPlayable() throws {
        let now = try date("2026-08-10")
        let model = DailyModel(repository: InMemoryGameRepository(), now: now)

        for cell in model.cells where cell.date != nil {
            let expected = (cell.dayNumber ?? 0) <= 10
            #expect(model.isPlayable(cell, now: now) == expected, "day \(cell.dayNumber ?? 0)")
        }

        let today = try #require(model.cells.first { model.isToday($0, now: now) })
        #expect(today.dayNumber == 10)
    }

    // MARK: - Reminders

    @Test("no reminder for today once today is done")
    func noReminderWhenTodayIsComplete() throws {
        let now = try date("2026-08-10").addingTimeInterval(3600 * 8)

        let reminders = StreakReminderPlan.reminders(
            now: now,
            hour: 19,
            streak: 5,
            isTodayCompleted: true,
            calendar: .utc
        )

        #expect(!reminders.contains { $0.dateKey == "2026-08-10" })
        #expect(reminders.first?.dateKey == "2026-08-11")
    }

    @Test("only tonight's reminder claims the streak")
    func onlyTonightMentionsTheStreak() throws {
        let now = try date("2026-08-10").addingTimeInterval(3600 * 8)

        let reminders = StreakReminderPlan.reminders(
            now: now,
            hour: 19,
            streak: 12,
            isTodayCompleted: false,
            calendar: .utc
        )

        let tonight = try #require(reminders.first)
        #expect(tonight.dateKey == "2026-08-10")
        #expect(tonight.body.contains("12 days"))
        // Tomorrow's fires after a day that may already have broken the streak,
        // so it must not assert anything about it.
        #expect(reminders.dropFirst().allSatisfy { !$0.body.contains("12") })
    }

    @Test("a streak of one is not '1 days'")
    func singularStreak() throws {
        let now = try date("2026-08-10")
        let reminders = StreakReminderPlan.reminders(
            now: now,
            hour: 19,
            streak: 1,
            isTodayCompleted: false,
            calendar: .utc
        )
        #expect(try #require(reminders.first).body.contains("1 day so far"))
    }

    @Test("reminders are in the future, in order, and no more than the horizon")
    func remindersAreWellFormed() throws {
        let now = try date("2026-08-10").addingTimeInterval(3600 * 20)

        let reminders = StreakReminderPlan.reminders(
            now: now,
            hour: 19,
            streak: 3,
            isTodayCompleted: false,
            calendar: .utc
        )

        #expect(reminders.count <= StreakReminderPlan.horizon)
        #expect(!reminders.isEmpty)
        #expect(reminders.allSatisfy { $0.fireDate > now })
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        #expect(Set(reminders.map(\.id)).count == reminders.count, "identifiers must not collide")
        // 7 pm UTC has already gone by 8 pm, so today drops out.
        #expect(reminders.first?.dateKey == "2026-08-11")
    }

    /// The one that is easy to get wrong: a local evening can fall outside the
    /// UTC day it is meant to protect, in either direction.
    @Test(
        "every fire time lands inside the UTC day it protects",
        arguments: [
            "UTC", "America/St_Johns", "America/Los_Angeles", "Pacific/Pago_Pago",
            "Pacific/Kiritimati", "Asia/Tokyo", "Asia/Kathmandu", "Europe/Madrid",
        ]
    )
    func fireTimesStayInsideTheirDay(zone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))

        for key in ["2026-01-15", "2026-03-29", "2026-08-10", "2026-11-01"] {
            let day = try date(key)
            let deadline = try #require(DailyPuzzle.calendar.date(byAdding: .day, value: 1, to: day))

            for hour in [17, 19, 22] {
                let fire = try #require(
                    StreakReminderPlan.fireDate(on: day, hour: hour, calendar: calendar),
                    "\(zone) \(key) at \(hour)"
                )
                #expect(fire >= day, "\(zone) \(key) at \(hour): fired before the day began")
                #expect(fire < deadline, "\(zone) \(key) at \(hour): fired after the day ended")
            }
        }
    }
}

extension Calendar {
    /// A UTC calendar, so reminder tests do not depend on the machine's zone.
    fileprivate static var utc: Calendar { DailyPuzzle.calendar }
}
