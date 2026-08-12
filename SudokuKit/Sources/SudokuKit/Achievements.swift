/// One achievement a player can unlock.
///
/// Port of `backend/internal/achievements/achievements.go`.
public struct Achievement: Equatable, Sendable, Identifiable {
    public let key: String
    /// Icon family: star, zap, trophy, fire.
    public let icon: String

    public var id: String { key }

    /// Title, translated.
    ///
    /// Looked up on each access rather than stored, because the catalogue is a
    /// `static let`: a stored name would be resolved the first time anything
    /// touched `Achievements.all` and then be that language for the rest of the
    /// process. That is invisible in the app, where the language cannot change
    /// under a running process, and wrong in the tests, which switch language
    /// deliberately.
    public var name: String { Copy.text("achievement.\(key).name") }

    /// What unlocks it, translated. Resolved per access, as `name` is.
    public var detail: String { Copy.text("achievement.\(key).detail") }

    public init(key: String, icon: String) {
        self.key = key
        self.icon = icon
    }
}

/// The achievement catalogue and unlock rules.
///
/// **The 11 keys are frozen.** They match the web app's `user_achievements`
/// table, so a future sync can reconcile the two without a migration. New rungs
/// (Expert) map onto the existing "hard" achievements rather than
/// redefining them; genuinely new achievements get genuinely new keys.
public enum Achievements {
    /// The canonical list, in display order.
    ///
    /// Key and icon only: the title and the description live in
    /// `Localizable.strings` under `achievement.<key>.name` and
    /// `achievement.<key>.detail`, which is also why the keys being frozen
    /// matters twice over — they are the join to the web app's table *and* the
    /// join to every translation.
    public static let all: [Achievement] = [
        // First solve per difficulty.
        Achievement(key: "first_easy_solve", icon: "star"),
        Achievement(key: "first_medium_solve", icon: "star"),
        Achievement(key: "first_hard_solve", icon: "star"),

        // Speed.
        Achievement(key: "speed_easy_5m", icon: "zap"),
        Achievement(key: "speed_medium_10m", icon: "zap"),
        Achievement(key: "speed_hard_20m", icon: "zap"),

        // Milestones.
        Achievement(key: "games_10", icon: "trophy"),
        Achievement(key: "games_50", icon: "trophy"),
        Achievement(key: "games_100", icon: "trophy"),

        // Streaks.
        Achievement(key: "streak_7", icon: "fire"),
        Achievement(key: "streak_30", icon: "fire"),
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

        // Expert counts as "hard" for continuity with the web app's three-rung
        // achievement set.
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

    /// Collapses the four-rung ladder onto the web app's three achievement
    /// buckets. Expert is harder than Hard, so it satisfies anything Hard does.
    static func achievementDifficulty(_ difficulty: Difficulty) -> Difficulty {
        switch difficulty {
        case .easy: .easy
        case .medium: .medium
        case .hard, .expert: .hard
        }
    }
}
