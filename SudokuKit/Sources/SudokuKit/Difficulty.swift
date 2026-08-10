/// The difficulty ladder.
///
/// The web app ships three rungs (`generator.go:24-31`). The technique rater
/// makes two more nearly free, and players expect five.
///
/// Every rung caps `maxTier` at `.advanced`, so **no shipped puzzle ever
/// requires guessing**. That is the differentiator worth protecting: "hard"
/// means "needs an X-wing", not "needs luck".
public enum Difficulty: String, CaseIterable, Sendable, Codable {
    case easy
    case medium
    case hard
    case expert
    case evil

    /// Display name.
    public var name: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// How the generator carves for this rung.
    public var spec: DifficultySpec {
        switch self {
        // Solvable by scanning alone — singles only, nothing to spot.
        case .easy: DifficultySpec(minTier: .nakedSingle, maxTier: .hiddenSingle, minClues: 34, attempts: 10)
        // Needs locked candidates or a naked pair at least once.
        case .medium: DifficultySpec(minTier: .locked, maxTier: .locked, minClues: 30, attempts: 60)
        // Locked candidates throughout, sometimes an advanced pattern.
        case .hard: DifficultySpec(minTier: .locked, maxTier: .advanced, minClues: 26, attempts: 80)
        // The web app's "hard": needs a hidden pair, naked triple, or X-wing.
        case .expert: DifficultySpec(minTier: .advanced, maxTier: .advanced, minClues: 22, attempts: 80)
        // Expert with the clue floor dropped to the theoretical minimum, so the
        // carve goes as deep as logic allows. Still never needs guessing.
        case .evil: DifficultySpec(minTier: .advanced, maxTier: .advanced, minClues: 17, attempts: 120)
        }
    }
}

/// Defines a difficulty by the solving techniques it requires.
///
/// Port of `difficultySpec` (`generator.go:13-18`). Clue count only sets a floor
/// so puzzles never look absurdly sparse; the tier bounds are what actually
/// decide how hard the puzzle plays.
public struct DifficultySpec: Equatable, Sendable {
    /// The puzzle must need at least this technique.
    public let minTier: Tier
    /// The puzzle must never need more than this.
    public let maxTier: Tier
    /// Stop carving at this many givens.
    public let minClues: Int
    /// Carve attempts before falling back to the closest match.
    ///
    /// Budgets differ because harder puzzles are rarer: a maximal carve lands on
    /// `.advanced` roughly 10% of the time, so the harder rungs need more
    /// samples. Generation returns on the first in-band puzzle, so the typical
    /// cost is far below the worst case.
    public let attempts: Int

    public init(minTier: Tier, maxTier: Tier, minClues: Int, attempts: Int) {
        self.minTier = minTier
        self.maxTier = maxTier
        self.minClues = minClues
        self.attempts = attempts
    }

    /// True when a rating falls inside this rung's band.
    public func accepts(_ tier: Tier) -> Bool {
        tier >= minTier && tier <= maxTier
    }
}
