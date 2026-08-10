/// Candidate sets as `UInt16` bitmasks, bits 1…9.
///
/// Port of the representation in `difficulty.go` (`allCandidates = 0x03FE` and
/// the `[9][9]uint16` candidate table). Bit 0 is deliberately unused so a digit
/// maps to its own bit position — `1 << n` — which makes every technique read
/// the same as the Go original.
public enum Candidates {
    /// Bits 1…9 set.
    public static let all: UInt16 = 0x03FE

    /// The bit for a single digit.
    @inlinable public static func bit(_ digit: Int) -> UInt16 { UInt16(1) << UInt16(digit) }

    /// How many digits a mask holds. Go: `bits.OnesCount16`.
    @inlinable public static func count(_ mask: UInt16) -> Int { mask.nonzeroBitCount }

    /// The smallest digit in a mask, or 0 when empty. Go: `bits.TrailingZeros16`.
    @inlinable public static func lowest(_ mask: UInt16) -> Int {
        mask == 0 ? 0 : mask.trailingZeroBitCount
    }

    /// The digits in a mask, ascending.
    public static func digits(_ mask: UInt16) -> [Int] {
        (1...Grid.size).filter { mask & bit($0) != 0 }
    }

    /// Builds a mask from digits.
    public static func mask(of digits: some Sequence<Int>) -> UInt16 {
        digits.reduce(into: UInt16(0)) { mask, digit in mask |= bit(digit) }
    }

    /// Calls `body` for each digit in the mask, ascending, without allocating.
    @inlinable
    public static func forEach(_ mask: UInt16, _ body: (Int) throws -> Void) rethrows {
        var remaining = mask
        while remaining != 0 {
            let digit = remaining.trailingZeroBitCount
            try body(digit)
            remaining &= remaining - 1
        }
    }
}

/// The candidate table for a grid: 81 masks, one per cell, empty for filled cells.
///
/// Used by the hint engine and the UI (auto-pencil). The technique solver keeps
/// its own copy on raw buffers to stay allocation-free in the carve loop.
public struct CandidateGrid: Equatable, Sendable {
    @usableFromInline internal var masks: ContiguousArray<UInt16>

    /// Computes candidates for every empty cell of `grid`.
    public init(_ grid: borrowing Grid) {
        var masks = ContiguousArray<UInt16>(repeating: 0, count: Grid.cellCount)
        grid.withUnsafeCells { cells in
            for index in 0..<Grid.cellCount where cells[index] == 0 {
                masks[index] = Candidates.all
            }
            for index in 0..<Grid.cellCount {
                let value = cells[index]
                guard value != 0 else { continue }
                let clear = ~Candidates.bit(Int(value))
                for peer in Units.peers(of: index) {
                    masks[peer] &= clear
                }
            }
        }
        self.masks = masks
    }

    @inlinable
    public subscript(index: Int) -> UInt16 { masks[index] }

    @inlinable
    public subscript(cell: CellRef) -> UInt16 { masks[cell.index] }

    @inlinable
    public subscript(row: Int, col: Int) -> UInt16 { masks[row * Grid.size + col] }

    /// True when some *empty* cell has no candidate left — the grid contradicts itself.
    ///
    /// Filled cells also carry an empty mask, so the grid is needed to tell the
    /// two cases apart. Go: `techSolver.stuck` (`difficulty.go:112-121`).
    public func hasContradiction(in grid: borrowing Grid) -> Bool {
        grid.withUnsafeCells { cells in
            for index in 0..<Grid.cellCount where cells[index] == 0 && masks[index] == 0 {
                return true
            }
            return false
        }
    }
}
