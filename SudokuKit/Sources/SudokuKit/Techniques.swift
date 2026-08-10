/// A human-technique Sudoku solver.
///
/// Line-by-line port of `techSolver` and its techniques
/// (`backend/internal/generator/difficulty.go:60-509`).
///
/// This is the most valuable code in the project and the part most Sudoku apps
/// get wrong: difficulty is defined by *which technique a human needs*, not by
/// clue count.
///
/// The solver works on caller-supplied buffers for both the grid and its 81
/// candidate masks, so the carve loop can run it thousands of times without
/// touching the allocator.
struct TechniqueSolver {
    private let cells: UnsafeMutableBufferPointer<UInt8>
    private let candidates: UnsafeMutableBufferPointer<UInt16>
    private let units: ContiguousArray<Int>

    private(set) var emptyCount: Int

    /// The first step taken since the last reset, when step recording is on.
    /// Drives the hint engine; always nil for plain rating.
    private(set) var lastStep: TechniqueStep?
    private let recordsSteps: Bool

    /// Builds the initial candidate table. Go: `newTechSolver` (l.67-87).
    init(
        cells: UnsafeMutableBufferPointer<UInt8>,
        candidates: UnsafeMutableBufferPointer<UInt16>,
        recordsSteps: Bool = false
    ) {
        self.cells = cells
        self.candidates = candidates
        self.units = Units.flat
        self.recordsSteps = recordsSteps

        var empty = 0
        for index in 0..<Grid.cellCount {
            if cells[index] == 0 {
                empty += 1
                candidates[index] = Candidates.all
            } else {
                candidates[index] = 0
            }
        }
        self.emptyCount = empty

        // Remove candidates conflicting with the givens.
        for index in 0..<Grid.cellCount where cells[index] != 0 {
            eliminatePeers(of: index, digit: Int(cells[index]))
        }
    }

    // MARK: - Primitives

    /// Clears `digit` from every peer's candidates. Go: `eliminatePeers` (l.90-102).
    private func eliminatePeers(of index: Int, digit: Int) {
        let clear = ~Candidates.bit(digit)
        let row = index / Grid.size
        let col = index % Grid.size

        let rowBase = row * Grid.size
        for i in 0..<Grid.size {
            candidates[rowBase + i] &= clear
            candidates[i * Grid.size + col] &= clear
        }
        let boxRow = row / Grid.boxSize * Grid.boxSize
        let boxCol = col / Grid.boxSize * Grid.boxSize
        for r in boxRow..<(boxRow + Grid.boxSize) {
            let base = r * Grid.size
            for c in boxCol..<(boxCol + Grid.boxSize) {
                candidates[base + c] &= clear
            }
        }
    }

    private mutating func place(_ index: Int, digit: Int) {
        cells[index] = UInt8(digit)
        candidates[index] = 0
        emptyCount -= 1
        eliminatePeers(of: index, digit: digit)
    }

    /// True when an empty cell has no candidate left — a contradiction.
    /// Go: `stuck` (l.112-121).
    var isStuck: Bool {
        for index in 0..<Grid.cellCount where cells[index] == 0 && candidates[index] == 0 {
            return true
        }
        return false
    }

    /// Candidates for one cell, for the hint engine and auto-pencil.
    func candidateMask(at index: Int) -> UInt16 { candidates[index] }

    /// Records the first step of a pass. Later steps in the same pass are
    /// ignored: a hint should explain one deduction, not a batch of them.
    private mutating func record(_ step: @autoclosure () -> TechniqueStep) {
        guard recordsSteps, lastStep == nil else { return }
        lastStep = step()
    }

    // MARK: - Singles

    /// Places every cell down to one candidate. Go: `nakedSingles` (l.165-179).
    mutating func nakedSingles() -> Bool {
        var progress = false
        for index in 0..<Grid.cellCount where cells[index] == 0 {
            guard candidates[index].nonzeroBitCount == 1 else { continue }
            let digit = Candidates.lowest(candidates[index])
            record(.nakedSingle(cell: CellRef(index: index), digit: digit))
            place(index, digit: digit)
            progress = true
        }
        return progress
    }

    /// Places digits with exactly one home in a unit. Go: `hiddenSingles` (l.182-208).
    mutating func hiddenSingles() -> Bool {
        var progress = false
        for unitIndex in 0..<Units.count {
            let base = unitIndex * Grid.size
            for digit in 1...Grid.size {
                let bit = Candidates.bit(digit)
                var count = 0
                var home = -1
                var alreadyPlaced = false

                for offset in 0..<Grid.size {
                    let index = units[base + offset]
                    if cells[index] == UInt8(digit) {
                        alreadyPlaced = true
                        break
                    }
                    if cells[index] == 0, candidates[index] & bit != 0 {
                        count += 1
                        home = index
                    }
                }

                guard !alreadyPlaced, count == 1 else { continue }
                record(
                    .hiddenSingle(
                        cell: CellRef(index: home),
                        digit: digit,
                        unit: UnitRef(unitIndex: unitIndex)
                    )
                )
                place(home, digit: digit)
                progress = true
            }
        }
        return progress
    }

    // MARK: - Locked candidates

    /// Pointing (box → line) and claiming (line → box).
    /// Go: `lockedCandidates` (l.211-312).
    mutating func lockedCandidates() -> Bool {
        var progress = false

        for digit in 1...Grid.size {
            let bit = Candidates.bit(digit)
            progress = pointing(digit: digit, bit: bit) || progress
            progress = claimingRows(digit: digit, bit: bit) || progress
            progress = claimingColumns(digit: digit, bit: bit) || progress
        }

        return progress
    }

    /// A digit confined to one row or column within a box cannot appear
    /// elsewhere on that line.
    private mutating func pointing(digit: Int, bit: UInt16) -> Bool {
        var progress = false

        for boxRow in stride(from: 0, to: Grid.size, by: Grid.boxSize) {
            for boxCol in stride(from: 0, to: Grid.size, by: Grid.boxSize) {
                var rowMask = 0
                var colMask = 0
                var found = false

                for r in boxRow..<(boxRow + Grid.boxSize) {
                    for c in boxCol..<(boxCol + Grid.boxSize) {
                        let index = r * Grid.size + c
                        if cells[index] == 0, candidates[index] & bit != 0 {
                            rowMask |= 1 << r
                            colMask |= 1 << c
                            found = true
                        }
                    }
                }
                guard found else { continue }

                if rowMask.nonzeroBitCount == 1 {
                    let r = rowMask.trailingZeroBitCount
                    var eliminated: [CellRef] = []
                    for c in 0..<Grid.size where c < boxCol || c >= boxCol + Grid.boxSize {
                        if eliminate(bit, at: r * Grid.size + c, into: &eliminated) { progress = true }
                    }
                    recordLocked(digit: digit, boxRow: boxRow, boxCol: boxCol, line: .row(r), eliminated: eliminated)
                }

                if colMask.nonzeroBitCount == 1 {
                    let c = colMask.trailingZeroBitCount
                    var eliminated: [CellRef] = []
                    for r in 0..<Grid.size where r < boxRow || r >= boxRow + Grid.boxSize {
                        if eliminate(bit, at: r * Grid.size + c, into: &eliminated) { progress = true }
                    }
                    recordLocked(
                        digit: digit, boxRow: boxRow, boxCol: boxCol, line: .column(c), eliminated: eliminated
                    )
                }
            }
        }

        return progress
    }

    /// A digit confined to one box within a row cannot appear elsewhere in that box.
    private mutating func claimingRows(digit: Int, bit: UInt16) -> Bool {
        var progress = false

        for r in 0..<Grid.size {
            var boxMask = 0
            var found = false
            for c in 0..<Grid.size {
                let index = r * Grid.size + c
                if cells[index] == 0, candidates[index] & bit != 0 {
                    boxMask |= 1 << (c / Grid.boxSize)
                    found = true
                }
            }
            guard found, boxMask.nonzeroBitCount == 1 else { continue }

            let boxCol = boxMask.trailingZeroBitCount * Grid.boxSize
            let boxRow = r / Grid.boxSize * Grid.boxSize
            var eliminated: [CellRef] = []
            for rr in boxRow..<(boxRow + Grid.boxSize) where rr != r {
                for c in boxCol..<(boxCol + Grid.boxSize)
                where eliminate(bit, at: rr * Grid.size + c, into: &eliminated) {
                    progress = true
                }
            }
            recordLocked(digit: digit, boxRow: boxRow, boxCol: boxCol, line: .row(r), eliminated: eliminated)
        }

        return progress
    }

    private mutating func claimingColumns(digit: Int, bit: UInt16) -> Bool {
        var progress = false

        for c in 0..<Grid.size {
            var boxMask = 0
            var found = false
            for r in 0..<Grid.size {
                let index = r * Grid.size + c
                if cells[index] == 0, candidates[index] & bit != 0 {
                    boxMask |= 1 << (r / Grid.boxSize)
                    found = true
                }
            }
            guard found, boxMask.nonzeroBitCount == 1 else { continue }

            let boxRow = boxMask.trailingZeroBitCount * Grid.boxSize
            let boxCol = c / Grid.boxSize * Grid.boxSize
            var eliminated: [CellRef] = []
            for cc in boxCol..<(boxCol + Grid.boxSize) where cc != c {
                for r in boxRow..<(boxRow + Grid.boxSize)
                where eliminate(bit, at: r * Grid.size + cc, into: &eliminated) {
                    progress = true
                }
            }
            recordLocked(digit: digit, boxRow: boxRow, boxCol: boxCol, line: .column(c), eliminated: eliminated)
        }

        return progress
    }

    /// Clears one candidate bit, reporting whether anything changed.
    private func eliminate(_ bit: UInt16, at index: Int, into eliminated: inout [CellRef]) -> Bool {
        guard cells[index] == 0, candidates[index] & bit != 0 else { return false }
        candidates[index] &= ~bit
        if recordsSteps { eliminated.append(CellRef(index: index)) }
        return true
    }

    private mutating func recordLocked(
        digit: Int, boxRow: Int, boxCol: Int, line: UnitRef, eliminated: [CellRef]
    ) {
        guard recordsSteps, !eliminated.isEmpty else { return }
        let box = (boxRow / Grid.boxSize) * Grid.boxSize + boxCol / Grid.boxSize
        record(.lockedCandidate(digit: digit, box: box, line: line, eliminates: eliminated))
    }

    // MARK: - Subsets

    /// k cells in a unit sharing exactly k candidates strip those digits from
    /// the rest of the unit. Go: `nakedSubsets` (l.316-357).
    ///
    /// **One deliberate divergence from the Go original.** Go builds a
    /// `map[[2]int]bool` per combination to test subset membership (l.338). A
    /// dictionary allocation inside this loop costs far more in Swift than in
    /// Go, so membership is a `UInt16` bitmask of unit-relative positions
    /// instead. Same semantics, no allocation.
    mutating func nakedSubsets(_ k: Int) -> Bool {
        var progress = false

        for unitIndex in 0..<Units.count {
            let base = unitIndex * Grid.size

            var open: [Int] = []
            open.reserveCapacity(Grid.size)
            for offset in 0..<Grid.size {
                let index = units[base + offset]
                if cells[index] == 0, candidates[index].nonzeroBitCount <= k {
                    open.append(offset)
                }
            }
            guard open.count > k else { continue }

            var pending: TechniqueStep?
            forEachCombination(of: open.count, choose: k) { pick in
                var digitMask: UInt16 = 0
                var memberMask: UInt16 = 0
                for slot in pick {
                    let offset = open[slot]
                    digitMask |= candidates[units[base + offset]]
                    memberMask |= UInt16(1) << UInt16(offset)
                }
                guard digitMask.nonzeroBitCount == k else { return false }

                var eliminated: [CellRef] = []
                for offset in 0..<Grid.size where memberMask & (UInt16(1) << UInt16(offset)) == 0 {
                    if eliminate(digitMask, at: units[base + offset], into: &eliminated) { progress = true }
                }

                if recordsSteps, !eliminated.isEmpty, pending == nil {
                    pending = .nakedSubset(
                        cells: pick.map { CellRef(index: units[base + open[$0]]) },
                        digits: Candidates.digits(digitMask),
                        unit: UnitRef(unitIndex: unitIndex),
                        eliminates: eliminated
                    )
                }
                return false
            }
            if let pending { record(pending) }
        }

        return progress
    }

    /// k digits confined to exactly k cells strip every other candidate from
    /// those cells. Go: `hiddenSubsets` (l.361-412).
    mutating func hiddenSubsets(_ k: Int) -> Bool {
        var progress = false

        for unitIndex in 0..<Units.count {
            let base = unitIndex * Grid.size

            // positions[n] = bitmask of unit-relative slots where digit n can go.
            var positions = [UInt16](repeating: 0, count: Grid.size + 1)
            for digit in 1...Grid.size {
                let bit = Candidates.bit(digit)
                for offset in 0..<Grid.size {
                    let index = units[base + offset]
                    if cells[index] == 0, candidates[index] & bit != 0 {
                        positions[digit] |= UInt16(1) << UInt16(offset)
                    }
                }
            }

            var digits: [Int] = []
            for digit in 1...Grid.size {
                let count = positions[digit].nonzeroBitCount
                if count >= 2, count <= k { digits.append(digit) }
            }
            guard digits.count >= k else { continue }

            var pending: TechniqueStep?
            forEachCombination(of: digits.count, choose: k) { pick in
                var positionMask: UInt16 = 0
                var digitMask: UInt16 = 0
                for slot in pick {
                    positionMask |= positions[digits[slot]]
                    digitMask |= Candidates.bit(digits[slot])
                }
                guard positionMask.nonzeroBitCount == k else { return false }

                var touched: [CellRef] = []
                for offset in 0..<Grid.size where positionMask & (UInt16(1) << UInt16(offset)) != 0 {
                    let index = units[base + offset]
                    guard candidates[index] & ~digitMask != 0 else { continue }
                    candidates[index] &= digitMask
                    if recordsSteps { touched.append(CellRef(index: index)) }
                    progress = true
                }

                if recordsSteps, !touched.isEmpty, pending == nil {
                    pending = .hiddenSubset(
                        cells: touched,
                        digits: pick.map { digits[$0] },
                        unit: UnitRef(unitIndex: unitIndex)
                    )
                }
                return false
            }
            if let pending { record(pending) }
        }

        return progress
    }

    // MARK: - X-wing

    /// Two lines where a digit sits in the same two crossing positions eliminate
    /// that digit elsewhere on those crossings. Go: `xWing` (l.415-489).
    mutating func xWing() -> Bool {
        var progress = false

        for digit in 1...Grid.size {
            let bit = Candidates.bit(digit)

            // Row-based: two rows where the digit shares the same two columns.
            var rowCols = [UInt16](repeating: 0, count: Grid.size)
            for r in 0..<Grid.size {
                for c in 0..<Grid.size {
                    let index = r * Grid.size + c
                    if cells[index] == 0, candidates[index] & bit != 0 {
                        rowCols[r] |= UInt16(1) << UInt16(c)
                    }
                }
            }
            for r1 in 0..<Grid.size where rowCols[r1].nonzeroBitCount == 2 {
                for r2 in (r1 + 1)..<Grid.size where rowCols[r2] == rowCols[r1] {
                    var eliminated: [CellRef] = []
                    for c in 0..<Grid.size where rowCols[r1] & (UInt16(1) << UInt16(c)) != 0 {
                        for r in 0..<Grid.size where r != r1 && r != r2 {
                            if eliminate(bit, at: r * Grid.size + c, into: &eliminated) { progress = true }
                        }
                    }
                    if !eliminated.isEmpty {
                        record(.xWing(digit: digit, lines: [.row(r1), .row(r2)], eliminates: eliminated))
                    }
                }
            }

            // Column-based: two columns where the digit shares the same two rows.
            var colRows = [UInt16](repeating: 0, count: Grid.size)
            for c in 0..<Grid.size {
                for r in 0..<Grid.size {
                    let index = r * Grid.size + c
                    if cells[index] == 0, candidates[index] & bit != 0 {
                        colRows[c] |= UInt16(1) << UInt16(r)
                    }
                }
            }
            for c1 in 0..<Grid.size where colRows[c1].nonzeroBitCount == 2 {
                for c2 in (c1 + 1)..<Grid.size where colRows[c2] == colRows[c1] {
                    var eliminated: [CellRef] = []
                    for r in 0..<Grid.size where colRows[c1] & (UInt16(1) << UInt16(r)) != 0 {
                        for c in 0..<Grid.size where c != c1 && c != c2 {
                            if eliminate(bit, at: r * Grid.size + c, into: &eliminated) { progress = true }
                        }
                    }
                    if !eliminated.isEmpty {
                        record(.xWing(digit: digit, lines: [.column(c1), .column(c2)], eliminates: eliminated))
                    }
                }
            }
        }

        return progress
    }
}

/// Calls `body` with each k-sized combination of indices in `0..<n`,
/// stopping early if it returns true. Go: `forEachCombination` (l.493-509).
///
/// The `pick` buffer is reused across calls, exactly as in Go — this runs inside
/// the rater, which runs inside the carve loop, so an allocation per combination
/// would be felt.
@inline(__always)
func forEachCombination(of n: Int, choose k: Int, _ body: (UnsafeBufferPointer<Int>) -> Bool) {
    guard k > 0, k <= n else { return }
    withUnsafeTemporaryAllocation(of: Int.self, capacity: k) { pick in
        pick.initialize(repeating: 0)
        defer { pick.deinitialize() }

        func recurse(start: Int, depth: Int) -> Bool {
            if depth == k { return body(UnsafeBufferPointer(pick)) }
            var i = start
            while i <= n - (k - depth) {
                pick[depth] = i
                if recurse(start: i + 1, depth: depth + 1) { return true }
                i += 1
            }
            return false
        }
        _ = recurse(start: 0, depth: 0)
    }
}
