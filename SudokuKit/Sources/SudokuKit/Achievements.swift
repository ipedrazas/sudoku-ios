/// One achievement a player can unlock.
///
/// Port of `backend/internal/achievements/achievements.go`.
public struct Achievement: Equatable, Sendable, Identifiable {
    public let key: String
    public let name: String
    public let detail: String
    /// Icon family: star, zap, trophy, fire.
    public let icon: String

    public var id: String { key }

    public init(key: String, name: String, detail: String, icon: String) {
        self.key = key
        self.name = name
        self.detail = detail
        self.icon = icon
    }
}

/// The achievement catalogue and unlock rules.
///
/// **The 11 keys are frozen.** They match the web app's `user_achievements`
/// table, so a future sync can reconcile the two without a migration. New rungs
/// (Expert, Evil) map onto the existing "hard" achievements rather than
/// redefining them; genuinely new achievements get genuinely new keys.
public enum Achievements {
    /// The canonical list, in display order.
    public static let all: [Achievement] = [
        // First solve per difficulty.
        Achievement(
            key: "first_easy_solve", name: "Easy Start", detail: "Complete your first easy puzzle", icon: "star"),
        Achievement(
            key: "first_medium_solve", name: "Stepping Up", detail: "Complete your first medium puzzle", icon: "star"
        ),
        Achievement(key: "first_hard_solve", name: "Fearless", detail: "Complete your first hard puzzle", icon: "star"),

        // Speed.
        Achievement(
            key: "speed_easy_5m", name: "Quick Fingers", detail: "Solve an easy puzzle in under 5 minutes", icon: "zap"
        ),
        Achievement(
            key: "speed_medium_10m", name: "Sharp Mind", detail: "Solve a medium puzzle in under 10 minutes",
            icon: "zap"
        ),
        Achievement(
            key: "speed_hard_20m", name: "Lightning Solve", detail: "Solve a hard puzzle in under 20 minutes",
            icon: "zap"
        ),

        // Milestones.
        Achievement(key: "games_10", name: "Getting Started", detail: "Complete 10 games", icon: "trophy"),
        Achievement(key: "games_50", name: "Dedicated", detail: "Complete 50 games", icon: "trophy"),
        Achievement(key: "games_100", name: "Centurion", detail: "Complete 100 games", icon: "trophy"),

        // Streaks.
        Achievement(key: "streak_7", name: "Week Warrior", detail: "Maintain a 7-day solve streak", icon: "fire"),
        Achievement(key: "streak_30", name: "Monthly Master", detail: "Maintain a 30-day solve streak", icon: "fire"),
    ]

    private static let byKey: [String: Achievement] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.key, $0) }
    )

    public static func achievement(for key: String) -> Achievement? { byKey[key] }

    /// Everything needed to decide what a completion just unlocked.
    ///
    /// Port of `CompletionContext` (`achievements.go:50-56`).
    public struct CompletionContext: Sendable {
        public let difficulty: Difficulty
        public let timeSeconds: Int
        public let totalFinished: Int
        public let currentStreak: Int
        public let alreadyEarned: Set<String>

        public init(
            difficulty: Difficulty,
            timeSeconds: Int,
            totalFinished: Int,
            currentStreak: Int,
            alreadyEarned: Set<String>
        ) {
            self.difficulty = difficulty
            self.timeSeconds = timeSeconds
            self.totalFinished = totalFinished
            self.currentStreak = currentStreak
            self.alreadyEarned = alreadyEarned
        }
    }

    /// The keys newly earned by this completion. Pure, with no side effects.
    ///
    /// Port of `CheckNew` (`achievements.go:60-88`), including its ordering: the
    /// result is the catalogue order, which is what the unlock animation plays.
    public static func newlyEarned(_ context: CompletionContext) -> [String] {
        var earned: [String] = []

        func check(_ key: String, _ condition: Bool) {
            guard condition, !context.alreadyEarned.contains(key) else { return }
            earned.append(key)
        }

        // Expert and Evil count as "hard" for continuity with the web app's
        // three-rung achievement set.
        let bucket = achievementDifficulty(context.difficulty)

        check("first_easy_solve", bucket == .easy)
        check("first_medium_solve", bucket == .medium)
        check("first_hard_solve", bucket == .hard)

        check("speed_easy_5m", bucket == .easy && context.timeSeconds < 300)
        check("speed_medium_10m", bucket == .medium && context.timeSeconds < 600)
        check("speed_hard_20m", bucket == .hard && context.timeSeconds < 1200)

        check("games_10", context.totalFinished >= 10)
        check("games_50", context.totalFinished >= 50)
        check("games_100", context.totalFinished >= 100)

        check("streak_7", context.currentStreak >= 7)
        check("streak_30", context.currentStreak >= 30)

        return earned
    }

    /// Collapses the five-rung ladder onto the web app's three achievement
    /// buckets. Expert and Evil are harder than Hard, so they satisfy anything
    /// Hard satisfies.
    static func achievementDifficulty(_ difficulty: Difficulty) -> Difficulty {
        switch difficulty {
        case .easy: .easy
        case .medium: .medium
        case .hard, .expert, .evil: .hard
        }
    }
}
