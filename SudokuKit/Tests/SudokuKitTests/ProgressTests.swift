import Foundation
import Testing

@testable import SudokuKit

/// Ports the table from `backend/internal/achievements/achievements_test.go`.
@Suite("Achievements")
struct AchievementsTests {

    private func context(
        difficulty: Difficulty = .easy,
        time: Int = 1000,
        total: Int = 1,
        streak: Int = 0,
        earned: Set<String> = []
    ) -> Achievements.CompletionContext {
        Achievements.CompletionContext(
            difficulty: difficulty,
            timeSeconds: time,
            totalFinished: total,
            currentStreak: streak,
            alreadyEarned: earned
        )
    }

    /// The keys are frozen so a future sync can reconcile with the web app's
    /// `user_achievements` table. Renaming one silently orphans a player's
    /// unlocks.
    @Test("the eleven keys match the web app exactly")
    func keysAreFrozen() {
        #expect(
            Achievements.all.map(\.key) == [
                "first_easy_solve", "first_medium_solve", "first_hard_solve",
                "speed_easy_5m", "speed_medium_10m", "speed_hard_20m",
                "games_10", "games_50", "games_100",
                "streak_7", "streak_30",
            ]
        )
        #expect(Achievements.all.count == 11)
    }

    @Test("every key resolves to its definition")
    func lookup() {
        for achievement in Achievements.all {
            #expect(Achievements.achievement(for: achievement.key) == achievement)
        }
        #expect(Achievements.achievement(for: "nope") == nil)
    }

    @Test("a first easy solve unlocks the easy achievement")
    func firstEasySolve() {
        let earned = Achievements.newlyEarned(context(difficulty: .easy, time: 1000))
        #expect(earned.contains("first_easy_solve"))
        #expect(!earned.contains("first_medium_solve"))
        #expect(!earned.contains("speed_easy_5m"), "1000s is over the 5-minute mark")
    }

    @Test("a fast solve unlocks both first-solve and speed")
    func speedAchievements() {
        let earned = Achievements.newlyEarned(context(difficulty: .easy, time: 299))
        #expect(earned.contains("first_easy_solve"))
        #expect(earned.contains("speed_easy_5m"))
    }

    @Test("speed thresholds are exclusive at the boundary")
    func speedBoundaries() {
        #expect(!Achievements.newlyEarned(context(difficulty: .easy, time: 300)).contains("speed_easy_5m"))
        #expect(Achievements.newlyEarned(context(difficulty: .easy, time: 299)).contains("speed_easy_5m"))
        #expect(!Achievements.newlyEarned(context(difficulty: .medium, time: 600)).contains("speed_medium_10m"))
        #expect(Achievements.newlyEarned(context(difficulty: .medium, time: 599)).contains("speed_medium_10m"))
        #expect(!Achievements.newlyEarned(context(difficulty: .hard, time: 1200)).contains("speed_hard_20m"))
        #expect(Achievements.newlyEarned(context(difficulty: .hard, time: 1199)).contains("speed_hard_20m"))
    }

    @Test("already-earned achievements are not re-issued")
    func noDuplicates() {
        let earned = Achievements.newlyEarned(
            context(difficulty: .easy, time: 100, earned: ["first_easy_solve", "speed_easy_5m"])
        )
        #expect(!earned.contains("first_easy_solve"))
        #expect(!earned.contains("speed_easy_5m"))
    }

    @Test("milestones unlock at or above their threshold")
    func milestones() {
        #expect(!Achievements.newlyEarned(context(total: 9)).contains("games_10"))
        #expect(Achievements.newlyEarned(context(total: 10)).contains("games_10"))
        #expect(Achievements.newlyEarned(context(total: 100)).contains("games_100"))

        // Passing 100 in one go earns every milestone not already held.
        let earned = Achievements.newlyEarned(context(total: 100))
        #expect(earned.contains("games_10"))
        #expect(earned.contains("games_50"))
    }

    @Test("streak achievements unlock at their threshold")
    func streaks() {
        #expect(!Achievements.newlyEarned(context(streak: 6)).contains("streak_7"))
        #expect(Achievements.newlyEarned(context(streak: 7)).contains("streak_7"))
        #expect(Achievements.newlyEarned(context(streak: 30)).contains("streak_30"))
    }

    /// Expert and Evil are harder than Hard, so they satisfy anything Hard does.
    /// This keeps the web app's three-bucket achievement set meaningful across a
    /// five-rung ladder without inventing keys a future sync would not recognise.
    @Test("expert and evil count as hard", arguments: [Difficulty.hard, .expert, .evil])
    func harderRungsCountAsHard(difficulty: Difficulty) {
        let earned = Achievements.newlyEarned(context(difficulty: difficulty, time: 100))
        #expect(earned.contains("first_hard_solve"))
        #expect(earned.contains("speed_hard_20m"))
        #expect(!earned.contains("first_easy_solve"))
    }
}

/// Ports `GetStreakForUser` (`backend/internal/store/store.go:499-564`).
@Suite("Streak")
struct StreakTests {

    private let now = Date(timeIntervalSince1970: 1_786_320_000)  // 2026-08-10 UTC

    private func daysAgo(_ offsets: [Int]) -> [Date] {
        offsets.map { now.addingTimeInterval(Double(-$0) * 86_400) }
    }

    @Test("no completions means no streak")
    func empty() {
        #expect(Streak.compute(completions: [], now: now) == StreakInfo(current: 0, best: 0))
    }

    @Test("solving today starts a streak of one")
    func today() {
        let streak = Streak.compute(completions: daysAgo([0]), now: now)
        #expect(streak.current == 1)
        #expect(streak.best == 1)
    }

    @Test("consecutive days accumulate")
    func consecutive() {
        let streak = Streak.compute(completions: daysAgo([0, 1, 2, 3, 4]), now: now)
        #expect(streak.current == 5)
        #expect(streak.best == 5)
    }

    /// Yesterday still counts: the player has not missed a day, because today is
    /// not over. Getting this wrong resets streaks every morning.
    @Test("a streak ending yesterday is still active")
    func yesterdayIsStillActive() {
        let streak = Streak.compute(completions: daysAgo([1, 2, 3]), now: now)
        #expect(streak.current == 3)
    }

    @Test("a streak ending two days ago is broken")
    func twoDaysAgoIsBroken() {
        let streak = Streak.compute(completions: daysAgo([2, 3, 4]), now: now)
        #expect(streak.current == 0)
        #expect(streak.best == 3, "the run still counts towards the best streak")
    }

    @Test("a gap ends the current streak but not the best")
    func gapSplitsRuns() {
        // Days 0-1 now, and a longer run 5-9 earlier.
        let streak = Streak.compute(completions: daysAgo([0, 1, 5, 6, 7, 8, 9]), now: now)
        #expect(streak.current == 2)
        #expect(streak.best == 5)
    }

    @Test("several solves on one day count once")
    func sameDayDeduplicates() {
        let today = now
        let completions = [today, today.addingTimeInterval(3600), today.addingTimeInterval(7200)]
        let streak = Streak.compute(completions: completions, now: now)
        #expect(streak.current == 1)
        #expect(streak.best == 1)
    }

    @Test("ordering of the input does not matter")
    func orderIndependent() {
        let ordered = Streak.compute(completions: daysAgo([0, 1, 2]), now: now)
        let jumbled = Streak.compute(completions: daysAgo([2, 0, 1]), now: now)
        #expect(ordered == jumbled)
    }

    @Test("the current streak is never greater than the best")
    func currentNeverExceedsBest() {
        for offsets in [[0], [0, 1], [0, 1, 2, 5, 6], [3, 4, 5]] {
            let streak = Streak.compute(completions: daysAgo(offsets), now: now)
            #expect(streak.current <= streak.best)
        }
    }
}

/// Ports the shape of `store.Stats` (`store.go:241-252`).
@Suite("Stats")
struct StatsTests {

    private let now = Date(timeIntervalSince1970: 1_786_320_000)  // Monday 2026-08-10 UTC

    private func completion(_ difficulty: Difficulty, _ seconds: Int, daysAgo: Int) -> CompletionRecord {
        CompletionRecord(
            difficulty: difficulty,
            timeSeconds: seconds,
            completedAt: now.addingTimeInterval(Double(-daysAgo) * 86_400)
        )
    }

    @Test("an empty history aggregates to zeroes, not nils")
    func empty() {
        let stats = StatsAggregator.aggregate([], now: now)
        #expect(stats.totalFinished == 0)
        #expect(stats.byDifficulty[.easy] == 0)
        #expect(stats.timeStats.isEmpty)
        #expect(stats.streak == StreakInfo())
        #expect(stats.timeDistribution.count == 5, "the histogram keeps its buckets even when empty")
        #expect(stats.timeDistribution.map(\.count) == [0, 0, 0, 0, 0])
    }

    @Test("totals and per-difficulty counts")
    func counts() {
        let stats = StatsAggregator.aggregate(
            [
                completion(.easy, 100, daysAgo: 0),
                completion(.easy, 200, daysAgo: 1),
                completion(.hard, 900, daysAgo: 2),
            ],
            now: now
        )

        #expect(stats.totalFinished == 3)
        #expect(stats.byDifficulty[.easy] == 2)
        #expect(stats.byDifficulty[.hard] == 1)
        #expect(stats.byDifficulty[.medium] == 0)
    }

    @Test("per-difficulty average and best")
    func timeStats() {
        let stats = StatsAggregator.aggregate(
            [
                completion(.medium, 100, daysAgo: 0),
                completion(.medium, 300, daysAgo: 1),
                completion(.medium, 200, daysAgo: 2),
            ],
            now: now
        )

        let medium = stats.timeStats[.medium]
        #expect(medium?.count == 3)
        #expect(medium?.averageSeconds == 200)
        #expect(medium?.bestSeconds == 100)
        #expect(stats.timeStats[.easy] == nil, "a difficulty never played has no time stats")
    }

    /// Bucket edges match `bucketTimeDist` (`store.go:279-306`) exactly, so the
    /// histogram reads the same as the web app's.
    @Test("solve times fall into the web app's buckets")
    func timeDistribution() {
        let stats = StatsAggregator.aggregate(
            [
                completion(.easy, 119, daysAgo: 0),  // <2m
                completion(.easy, 120, daysAgo: 1),  // 2–5m
                completion(.easy, 299, daysAgo: 2),  // 2–5m
                completion(.easy, 599, daysAgo: 3),  // 5–10m
                completion(.easy, 1199, daysAgo: 4),  // 10–20m
                completion(.easy, 1200, daysAgo: 5),  // 20m+
            ],
            now: now
        )

        #expect(stats.timeDistribution.map(\.label) == ["<2m", "2–5m", "5–10m", "10–20m", "20m+"])
        #expect(stats.timeDistribution.map(\.count) == [1, 2, 1, 1, 1])
    }

    @Test("day-of-week keys from 0 = Sunday, matching the web app")
    func dayOfWeek() {
        // 2026-08-10 is a Monday.
        let stats = StatsAggregator.aggregate([completion(.easy, 100, daysAgo: 0)], now: now)
        #expect(stats.byDayOfWeek[1] == 1, "Monday should key to 1")
        #expect(stats.byDayOfWeek[0] == nil)
    }

    @Test("month and day keys are formatted for grouping")
    func periodKeys() {
        let stats = StatsAggregator.aggregate(
            [completion(.easy, 100, daysAgo: 0), completion(.easy, 100, daysAgo: 40)],
            now: now
        )
        #expect(stats.byMonth["2026-08"] == 1)
        #expect(stats.byMonth["2026-07"] == 1)
        #expect(stats.byDay["2026-08-10"] == 1)
    }

    @Test("the heatmap covers only the trailing year")
    func heatmapWindow() {
        let stats = StatsAggregator.aggregate(
            [completion(.easy, 100, daysAgo: 10), completion(.easy, 100, daysAgo: 400)],
            now: now
        )
        #expect(stats.byDay.values.reduce(0, +) == 1, "a completion older than a year is outside the heatmap")
        #expect(stats.totalFinished == 2, "but it still counts towards the total")
    }

    @Test("recent completions come back newest first and capped")
    func recentCompletions() {
        let completions = (0..<20).map { completion(.easy, 100 + $0, daysAgo: $0) }
        let stats = StatsAggregator.aggregate(completions, now: now, recentLimit: 5)

        #expect(stats.recentCompletions.count == 5)
        #expect(stats.recentCompletions.first?.completedAt == completions[0].completedAt)
        #expect(
            stats.recentCompletions.map(\.completedAt)
                == stats.recentCompletions.map(\.completedAt).sorted(by: >)
        )
    }

    @Test("the streak is computed from the same rows")
    func streakIsIncluded() {
        let stats = StatsAggregator.aggregate(
            [
                completion(.easy, 100, daysAgo: 0),
                completion(.easy, 100, daysAgo: 1),
                completion(.easy, 100, daysAgo: 2),
            ],
            now: now
        )
        #expect(stats.streak.current == 3)
    }
}
