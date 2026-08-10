/// How hard a puzzle is, defined by the hardest technique needed to finish it
/// without guessing.
///
/// Port of `generator.Tier` (`backend/internal/generator/difficulty.go:9-22`).
/// Clue count is a poor proxy for how hard a puzzle feels — a 25-clue grid can
/// fall to plain scanning while a 32-clue grid needs an X-wing — so difficulty
/// is defined by technique instead.
public enum Tier: Int, Comparable, Sendable, CaseIterable, Codable {
    /// Every cell falls to "only one digit fits here".
    case nakedSingle = 1
    /// Also needs "only one cell in this unit can hold n".
    case hiddenSingle = 2
    /// Also needs locked candidates or naked pairs.
    case locked = 3
    /// Also needs hidden pairs, naked triples, or an X-wing.
    case advanced = 4
    /// Not solvable by any of the above — needs chains or guessing. Never shipped.
    case beyond = 5

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Plain-language name, for hint copy and the import screen.
    public var name: String {
        switch self {
        case .nakedSingle: "naked singles"
        case .hiddenSingle: "hidden singles"
        case .locked: "locked candidates"
        case .advanced: "advanced patterns"
        case .beyond: "beyond logic"
        }
    }
}

/// Rates a puzzle by running a human-technique solver over it.
public enum Rater {
    /// The hardest tier needed to solve `puzzle` logically.
    ///
    /// Returns `.beyond` if the puzzle needs techniques past an X-wing, is
    /// contradictory, or has no unique logical path.
    ///
    /// Port of `Rate` (`difficulty.go:130-155`). **The order of the technique
    /// attempts below is the definition of difficulty** — cheapest first,
    /// returning the hardest tier reached. Reordering it re-rates every puzzle
    /// in existence, including every past daily. Do not "optimise" it.
    public static func rate(_ puzzle: borrowing Grid) -> Tier {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Grid.cellCount) { cells in
            puzzle.withUnsafeCells { source in
                _ = cells.initialize(fromContentsOf: source)
            }
            defer { cells.deinitialize() }

            return withUnsafeTemporaryAllocation(of: UInt16.self, capacity: Grid.cellCount) { candidates in
                candidates.initialize(repeating: 0)
                defer { candidates.deinitialize() }

                var solver = TechniqueSolver(cells: cells, candidates: candidates)
                var hardest = Tier.nakedSingle

                while solver.emptyCount > 0 {
                    if solver.isStuck { return .beyond }
                    if solver.nakedSingles() { continue }
                    if solver.hiddenSingles() {
                        hardest = max(hardest, .hiddenSingle)
                        continue
                    }
                    if solver.lockedCandidates() || solver.nakedSubsets(2) {
                        hardest = max(hardest, .locked)
                        continue
                    }
                    if solver.hiddenSubsets(2) || solver.nakedSubsets(3) || solver.xWing() {
                        hardest = max(hardest, .advanced)
                        continue
                    }
                    return .beyond
                }
                return hardest
            }
        }
    }

    /// Runs the technique solver one deduction at a time.
    ///
    /// Same loop as `rate`, but stops at the first step and reports it. This is
    /// what the hint engine drives, and it runs against the *player's* board
    /// rather than the original puzzle.
    public static func nextStep(for board: borrowing Grid) -> TechniqueStep? {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Grid.cellCount) { cells in
            board.withUnsafeCells { source in
                _ = cells.initialize(fromContentsOf: source)
            }
            defer { cells.deinitialize() }

            return withUnsafeTemporaryAllocation(of: UInt16.self, capacity: Grid.cellCount) { candidates in
                candidates.initialize(repeating: 0)
                defer { candidates.deinitialize() }

                var solver = TechniqueSolver(cells: cells, candidates: candidates, recordsSteps: true)
                guard solver.emptyCount > 0, !solver.isStuck else { return nil }

                if solver.nakedSingles() { return solver.lastStep }
                if solver.hiddenSingles() { return solver.lastStep }
                if solver.lockedCandidates() { return solver.lastStep }
                if solver.nakedSubsets(2) { return solver.lastStep }
                if solver.hiddenSubsets(2) { return solver.lastStep }
                if solver.nakedSubsets(3) { return solver.lastStep }
                if solver.xWing() { return solver.lastStep }
                return nil
            }
        }
    }
}
