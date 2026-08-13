/// The difficulty ladder.
///
/// The web app ships three rungs (`generator.go:24-31`); Expert is the fourth,
/// and it is where the ladder stops.
///
/// A fifth rung ("Evil", carving to the 17-clue theoretical minimum) was
/// specified and built, then measured and removed. It was indistinguishable
/// from Expert — both landed on a median of 24 clues with the same tier and the
/// same generation cost — because `minClues` is a stop-carving *floor* that
/// neither rung ever reaches. Carving halts earlier, when no further removal
/// keeps both a unique solution and a tier at or below `.advanced`, and the two
/// rungs shared that ceiling. Two labels for one generator is worse than four
/// honest rungs.
///
/// A genuine fifth rung needs a harder technique in the rater — an XY-wing or a
/// swordfish as a real tier 5 — not a lower clue floor.
///
/// Every rung caps `maxTier` at `.advanced`, so **no shipped puzzle ever
/// requires guessing**. That is the differentiator worth protecting: "hard"
/// means "needs an X-wing", not "needs luck".
/// Gentle was added below Easy after players reported the ladder starting too
/// high. It is added rather than folded in: every other rung keeps its spec
/// exactly, so every daily ever generated still generates the same puzzle.
/// Re-scaling the four existing rungs would have been the tidier menu and would
/// have quietly rewritten history.
public enum Difficulty: String, CaseIterable, Sendable, Codable {
    case gentle
    case easy
    case medium
    case hard
    case expert

    /// Display name, translated.
    ///
    /// `rawValue` stays English and lowercase — it is the `Codable`
    /// representation and it is written into the store, so it is not allowed to
    /// depend on what language the phone is set to.
    public var name: String {
        Copy.text("difficulty.\(rawValue)")
    }

    /// How the generator carves for this rung.
    public var spec: DifficultySpec {
        switch self {
        // Never anything but "this cell can only be one digit". No hidden
        // single, so a player who has not yet learned to scan a unit for a
        // digit's only home is never asked to.
        //
        // The clue floor is 40 and it is doing real work: below it the carve
        // starts needing hidden singles to stay unique, misses the band, and
        // falls back to a tier-2 puzzle — which is Easy wearing a gentler
        // label, the one thing this rung must not be.
        case .gentle: DifficultySpec(minTier: .nakedSingle, maxTier: .nakedSingle, minClues: 40, attempts: 20)
        // Solvable by scanning alone — singles only, nothing to spot.
        case .easy: DifficultySpec(minTier: .nakedSingle, maxTier: .hiddenSingle, minClues: 34, attempts: 10)
        // Needs locked candidates or a naked pair at least once.
        //
        // The floor is 28, not the 30 originally planned. Measured over 40
        // seeds, a floor of 30 stops the carve too early to force a locked
        // candidate and misses the band 4 times in 40, falling back to a tier-2
        // puzzle. Since medium is also the daily difficulty, that would mean
        // roughly three days a month quietly easier than advertised. At 28 the
        // hit rate is 40/40, and it stays clearly separated from hard's 26.
        case .medium: DifficultySpec(minTier: .locked, maxTier: .locked, minClues: 28, attempts: 60)
        // Locked candidates throughout, sometimes an advanced pattern.
        case .hard: DifficultySpec(minTier: .locked, maxTier: .advanced, minClues: 26, attempts: 80)
        // The web app's "hard": needs a hidden pair, naked triple, or X-wing.
        case .expert: DifficultySpec(minTier: .advanced, maxTier: .advanced, minClues: 22, attempts: 80)
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
