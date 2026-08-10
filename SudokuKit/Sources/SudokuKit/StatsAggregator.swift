import Foundation

/// One finished puzzle.
public struct CompletionRecord: Equatable, Sendable {
    public let difficulty: Difficulty
    public let timeSeconds: Int
    public let hintsUsed: Int
    public let completedAt: Date

    public init(difficulty: Difficulty, timeSeconds: Int, hintsUsed: Int = 0, completedAt: Date) {
        self.difficulty = difficulty
        self.timeSeconds = timeSeconds
        self.hintsUsed = hintsUsed
        self.completedAt = completedAt
    }
}

/// Time statistics for one difficulty.
public struct DifficultyTimeStats: Equatable, Sendable {
    public let count: Int
    public let averageSeconds: Double
    public let bestSeconds: Int

    public init(count: Int, averageSeconds: Double, bestSeconds: Int) {
        self.count = count
        self.averageSeconds = averageSeconds
        self.bestSeconds = bestSeconds
    }
}

/// One bucket of the solve-time histogram.
public struct TimeBucket: Equatable, Sendable, Identifiable {
    public let label: String
    public let count: Int

    public var id: String { label }

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }
}

/// The full local equivalent of the web app's `/api/stats` response.
///
/// Port of `store.Stats` (`backend/internal/store/store.go:241-252`). Keeping
/// the same shape means the Stats screen can be built against the web app's
/// existing design, and a future sync has an obvious mapping.
public struct Stats: Equatable, Sendable {
    public let totalFinished: Int
    public let byDifficulty: [Difficulty: Int]
    /// Keyed 0 = Sunday … 6 = Saturday, matching the web app.
    public let byDayOfWeek: [Int: Int]
    /// Keyed `"YYYY-MM"`.
    public let byMonth: [String: Int]
    public let timeStats: [Difficulty: DifficultyTimeStats]
    public let timeDistribution: [TimeBucket]
    public let streak: StreakInfo
    public let recentCompletions: [CompletionRecord]
    /// Completions per day over the trailing year, keyed `"YYYY-MM-DD"` — the
    /// contribution heatmap.
    public let byDay: [String: Int]

    public init(
        totalFinished: Int,
        byDifficulty: [Difficulty: Int],
        byDayOfWeek: [Int: Int],
        byMonth: [String: Int],
        timeStats: [Difficulty: DifficultyTimeStats],
        timeDistribution: [TimeBucket],
        streak: StreakInfo,
        recentCompletions: [CompletionRecord],
        byDay: [String: Int]
    ) {
        self.totalFinished = totalFinished
        self.byDifficulty = byDifficulty
        self.byDayOfWeek = byDayOfWeek
        self.byMonth = byMonth
        self.timeStats = timeStats
        self.timeDistribution = timeDistribution
        self.streak = streak
        self.recentCompletions = recentCompletions
        self.byDay = byDay
    }
}

/// Computes `Stats` from completion rows.
///
/// The web app did this in SQL across six queries. Here it is one pass over an
/// array, which is both simpler and, at the scale of one player's history,
/// faster than the round trip it replaces.
public enum StatsAggregator {

    /// Bucket edges in seconds, with the labels the web app uses
    /// (`store.go:279-306`).
    private static let bucketEdges: [(label: String, upperBound: Int)] = [
        ("<2m", 120),
        ("2–5m", 300),
        ("5–10m", 600),
        ("10–20m", 1200),
        ("20m+", .max),
    ]

    public static func aggregate(
        _ completions: [CompletionRecord],
        now: Date = Date(),
        recentLimit: Int = 10
    ) -> Stats {
        let calendar = DailyPuzzle.calendar

        var byDifficulty: [Difficulty: Int] = Difficulty.allCases.reduce(into: [:]) { $0[$1] = 0 }
        var byDayOfWeek: [Int: Int] = [:]
        var byMonth: [String: Int] = [:]
        var byDay: [String: Int] = [:]
        var timesByDifficulty: [Difficulty: [Int]] = [:]
        var bucketCounts = [Int](repeating: 0, count: bucketEdges.count)

        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)

        for completion in completions {
            byDifficulty[completion.difficulty, default: 0] += 1
            timesByDifficulty[completion.difficulty, default: []].append(completion.timeSeconds)

            let parts = calendar.dateComponents([.year, .month, .weekday], from: completion.completedAt)
            // Calendar.weekday is 1-based from Sunday; the web app keys from 0.
            byDayOfWeek[(parts.weekday ?? 1) - 1, default: 0] += 1
            byMonth[String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0), default: 0] += 1

            if let yearAgo, completion.completedAt >= yearAgo {
                byDay[DailyPuzzle.dateKey(for: completion.completedAt), default: 0] += 1
            }

            if let index = bucketEdges.firstIndex(where: { completion.timeSeconds < $0.upperBound }) {
                bucketCounts[index] += 1
            }
        }

        let timeStats = timesByDifficulty.compactMapValues { times -> DifficultyTimeStats? in
            guard let best = times.min() else { return nil }
            return DifficultyTimeStats(
                count: times.count,
                averageSeconds: Double(times.reduce(0, +)) / Double(times.count),
                bestSeconds: best
            )
        }

        return Stats(
            totalFinished: completions.count,
            byDifficulty: byDifficulty,
            byDayOfWeek: byDayOfWeek,
            byMonth: byMonth,
            timeStats: timeStats,
            timeDistribution: zip(bucketEdges, bucketCounts).map { TimeBucket(label: $0.label, count: $1) },
            streak: Streak.compute(completions: completions.map(\.completedAt), now: now),
            recentCompletions: Array(completions.sorted { $0.completedAt > $1.completedAt }.prefix(recentLimit)),
            byDay: byDay
        )
    }
}
