/// Backtracking solver and solution counter.
///
/// Port of `Solve`, `solveDeterministic`, `countSolutions`, `findBestEmptyCell`
/// and `candidatesFor` (`backend/internal/generator/generator.go:45-309`).
///
/// `countSolutions` runs once per removal attempt inside `carveToTier` — up to
/// 81 removals per attempt, up to 120 attempts for Evil — so it is the hottest
/// code in the package. It works entirely on stack-allocated scratch: no array
/// copies, no ARC traffic, no allocator calls in the recursion.
public enum Solver {
    /// Solves the puzzle, or returns nil if it is contradictory or unsolvable.
    ///
    /// Candidates are tried in ascending order, so the result is deterministic:
    /// the same puzzle always yields the same solution, whatever the RNG is doing.
    public static func solve(_ puzzle: borrowing Grid) -> Grid? {
        guard Validator.obeysRules(puzzle) else { return nil }
        var working = copy puzzle
        let solved = working.withUnsafeMutableCells { cells in
            solveRecursive(&cells, from: 0)
        }
        return solved ? working : nil
    }

    /// Counts solutions up to `limit`, stopping as soon as the limit is reached.
    ///
    /// Callers almost always want `limit: 2` — "exactly one" is the property
    /// that matters, and stopping at two makes proving it cheap.
    public static func countSolutions(_ puzzle: borrowing Grid, limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        // A contradiction among the *givens* is invisible to the search below:
        // it only ever inspects empty cells, so two 5s in one box would be
        // discovered only after exhausting the whole tree. Go's counter has the
        // same blind spot but never meets it, because it only runs on grids
        // carved from a valid solution. This one is public API and does.
        guard Validator.obeysRules(puzzle) else { return 0 }
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: Grid.cellCount) { scratch in
            puzzle.withUnsafeCells { cells in
                _ = scratch.initialize(fromContentsOf: cells)
            }
            defer { scratch.deinitialize() }
            return countRecursive(scratch, limit: limit)
        }
    }

    /// True when the puzzle has exactly one solution — the property every
    /// generated and imported puzzle must satisfy.
    public static func hasUniqueSolution(_ puzzle: borrowing Grid) -> Bool {
        countSolutions(puzzle, limit: 2) == 1
    }

    // MARK: - Recursion

    /// Fills cells in index order, trying digits ascending. Go: `solveDeterministic`.
    private static func solveRecursive(
        _ cells: inout UnsafeMutableBufferPointer<UInt8>,
        from index: Int
    ) -> Bool {
        guard index < Grid.cellCount else { return true }
        guard cells[index] == 0 else {
            return solveRecursive(&cells, from: index + 1)
        }

        var remaining = candidateMask(UnsafeBufferPointer(cells), at: index)
        while remaining != 0 {
            let digit = remaining.trailingZeroBitCount
            remaining &= remaining - 1
            cells[index] = UInt8(digit)
            if solveRecursive(&cells, from: index + 1) { return true }
            cells[index] = 0
        }
        return false
    }

    /// Go: `countSolutionsRecursive`. The `limit - count` arithmetic is ported
    /// verbatim — it is the early exit that keeps counting cheap, and getting it
    /// subtly wrong would make uniqueness checks either slow or incorrect.
    private static func countRecursive(
        _ cells: UnsafeMutableBufferPointer<UInt8>,
        limit: Int
    ) -> Int {
        guard limit > 0 else { return 0 }

        // No empty cells: a solution. Only legal candidates are ever placed, so
        // a grid that obeyed the rules on entry still obeys them here.
        guard let choice = bestEmptyCell(cells) else { return 1 }
        if choice.candidates == 0 { return 0 }

        var count = 0
        var remaining = choice.candidates
        while remaining != 0 {
            let digit = remaining.trailingZeroBitCount
            remaining &= remaining - 1
            cells[choice.index] = UInt8(digit)
            count += countRecursive(cells, limit: limit - count)
            if count >= limit {
                cells[choice.index] = 0
                return count
            }
        }
        cells[choice.index] = 0
        return count
    }

    // MARK: - Cell selection

    private struct Choice {
        let index: Int
        let candidates: UInt16
    }

    /// Minimum-remaining-values: the empty cell with the fewest candidates.
    ///
    /// Go: `findBestEmptyCell`. Returns nil only when the grid is full. A cell
    /// with zero candidates short-circuits immediately — that branch is dead, so
    /// there is no point searching further.
    private static func bestEmptyCell(_ cells: UnsafeMutableBufferPointer<UInt8>) -> Choice? {
        let readOnly = UnsafeBufferPointer(cells)
        var best: Choice?
        var bestCount = Grid.size + 1

        for index in 0..<Grid.cellCount where readOnly[index] == 0 {
            let candidates = candidateMask(readOnly, at: index)
            let count = candidates.nonzeroBitCount
            if count == 0 { return Choice(index: index, candidates: 0) }
            if count < bestCount {
                best = Choice(index: index, candidates: candidates)
                bestCount = count
                if count == 1 { return best }
            }
        }
        return best
    }

    /// Digits that could legally go in `index`, as a bitmask. Go: `candidatesFor`.
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

        // Empty peers set bit 0, which `Candidates.all` masks straight back off.
        return Candidates.all & ~used
    }
}
