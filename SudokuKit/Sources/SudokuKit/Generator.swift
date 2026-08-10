/// A generated puzzle together with the solution it was carved from.
public struct GeneratedPuzzle: Equatable, Sendable {
    public let puzzle: Grid
    public let solution: Grid
    public let difficulty: Difficulty
    /// The tier the puzzle actually rates, which may fall short of the target
    /// when the attempt budget runs out.
    public let tier: Tier

    public init(puzzle: Grid, solution: Grid, difficulty: Difficulty, tier: Tier) {
        self.puzzle = puzzle
        self.solution = solution
        self.difficulty = difficulty
        self.tier = tier
    }

    public var clueCount: Int { puzzle.clueCount }
}

/// Puzzle generation: fill a grid, then carve it down to a target difficulty.
///
/// Port of `Generate`, `generateSolution`, `backtrack` and `carveToTier`
/// (`backend/internal/generator/generator.go:121-227`).
///
/// Every returned puzzle has a unique solution and is solvable by logic alone:
/// carving never crosses the difficulty's `maxTier`, so "hard" never means
/// "guess".
public enum Generator {
    /// Generates a puzzle of the requested difficulty.
    ///
    /// The RNG is injected rather than global — that is what makes the daily
    /// puzzle reproducible on every device. See `SeededRandom`.
    public static func generate(_ difficulty: Difficulty, using rng: inout SeededRandom) -> GeneratedPuzzle {
        let spec = difficulty.spec

        var best: GeneratedPuzzle?

        for _ in 0..<spec.attempts {
            let solution = generateSolution(using: &rng)
            var puzzle = solution
            let tier = carveToTier(&puzzle, spec: spec, using: &rng)

            if spec.accepts(tier) {
                return GeneratedPuzzle(puzzle: puzzle, solution: solution, difficulty: difficulty, tier: tier)
            }

            // Keep the closest attempt so a run of bad luck still returns a
            // playable puzzle rather than an uncarved grid. Go: `generator.go:136`
            // uses a `bestTier` of 0, which no Tier case can represent — an
            // optional says the same thing without inventing a sentinel.
            if tier <= spec.maxTier, best.map({ tier > $0.tier }) ?? true {
                best = GeneratedPuzzle(puzzle: puzzle, solution: solution, difficulty: difficulty, tier: tier)
            }
        }

        if let best { return best }

        // Every attempt overshot the ceiling. Fall back to a fully solved grid
        // rather than returning something unsolvable — unreachable in practice,
        // but the alternative is shipping a broken puzzle.
        let solution = generateSolution(using: &rng)
        return GeneratedPuzzle(
            puzzle: solution, solution: solution, difficulty: difficulty, tier: .nakedSingle
        )
    }

    /// A complete, valid grid, filled by randomised backtracking.
    /// Go: `generateSolution` + `backtrack` (l.148-196).
    public static func generateSolution(using rng: inout SeededRandom) -> Grid {
        var grid = Grid()
        _ = grid.withUnsafeMutableCells { cells in
            fill(&cells, from: 0, using: &rng)
        }
        return grid
    }

    private static func fill(
        _ cells: inout UnsafeMutableBufferPointer<UInt8>,
        from index: Int,
        using rng: inout SeededRandom
    ) -> Bool {
        guard index < Grid.cellCount else { return true }
        guard cells[index] == 0 else {
            return fill(&cells, from: index + 1, using: &rng)
        }

        let mask = candidateMask(UnsafeBufferPointer(cells), at: index)
        guard mask != 0 else { return false }

        // Shuffling a local copy keeps the recursion allocation-light while
        // still drawing every choice from the injected RNG.
        var candidates = Candidates.digits(mask)
        candidates.deterministicShuffle(using: &rng)

        for digit in candidates {
            cells[index] = UInt8(digit)
            if fill(&cells, from: index + 1, using: &rng) { return true }
            cells[index] = 0
        }
        return false
    }

    /// Removes as many givens as possible without breaking uniqueness or
    /// pushing the puzzle past `spec.maxTier`, stopping at `spec.minClues`.
    ///
    /// Go: `carveToTier` (l.203-227). Carving as deep as the ceiling allows is
    /// what makes the result land *on* the target difficulty: a puzzle that
    /// could lose another clue and stay within the ceiling has not yet earned
    /// its rating.
    ///
    /// Returns the final tier.
    @discardableResult
    public static func carveToTier(
        _ puzzle: inout Grid,
        spec: DifficultySpec,
        using rng: inout SeededRandom
    ) -> Tier {
        var order = Array(0..<Grid.cellCount)
        order.deterministicShuffle(using: &rng)

        var clues = Grid.cellCount
        for index in order {
            if clues <= spec.minClues { break }
            let backup = puzzle[index]
            if backup == 0 { continue }

            puzzle[index] = 0
            if Solver.countSolutions(puzzle, limit: 2) != 1 || Rater.rate(puzzle) > spec.maxTier {
                puzzle[index] = backup
                continue
            }
            clues -= 1
        }

        return Rater.rate(puzzle)
    }

    /// Digits that could legally go in `index`. Go: `candidatesFor`.
    @inline(__always)
    private static func candidateMask(_ cells: UnsafeBufferPointer<UInt8>, at index: Int) -> UInt16 {
        let row = index / Grid.size
        let col = index % Grid.size
        var used: UInt16 = 0

        let rowBase = row * Grid.size
        for i in 0..<Grid.size {
            used |= UInt16(1) << UInt16(cells[rowBase + i])
            used |= UInt16(1) << UInt16(cells[i * Grid.size + col])
        }

        let boxRow = row / Grid.boxSize * Grid.boxSize
        let boxCol = col / Grid.boxSize * Grid.boxSize
        for r in boxRow..<(boxRow + Grid.boxSize) {
            let base = r * Grid.size
            for c in boxCol..<(boxCol + Grid.boxSize) {
                used |= UInt16(1) << UInt16(cells[base + c])
            }
        }

        return Candidates.all & ~used
    }
}
