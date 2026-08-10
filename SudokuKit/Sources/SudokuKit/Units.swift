/// The 27 units — 9 rows, 9 columns, 9 boxes — precomputed once.
///
/// Port of `buildUnits()` (`backend/internal/generator/difficulty.go:30-58`).
/// The ordering is load-bearing: rows 0…8, then columns 9…17, then boxes 18…26,
/// with boxes in reading order. `Rater` iterates units in this order, and unit
/// order affects which technique fires first and therefore the reported tier.
///
/// Storage is one flat 243-element buffer rather than `[[Int]]`: the technique
/// solver walks every unit on every pass, and a nested array would mean a retain
/// and a bounds check per inner access.
public enum Units {
    /// 27 units × 9 cell indices, flat.
    public static let flat: ContiguousArray<Int> = buildUnits()

    /// Number of units.
    public static let count = 27

    private static func buildUnits() -> ContiguousArray<Int> {
        var units = ContiguousArray<Int>()
        units.reserveCapacity(count * Grid.size)

        for r in 0..<Grid.size {
            for c in 0..<Grid.size {
                units.append(r * Grid.size + c)
            }
        }
        for c in 0..<Grid.size {
            for r in 0..<Grid.size {
                units.append(r * Grid.size + c)
            }
        }
        for br in stride(from: 0, to: Grid.size, by: Grid.boxSize) {
            for bc in stride(from: 0, to: Grid.size, by: Grid.boxSize) {
                for r in br..<(br + Grid.boxSize) {
                    for c in bc..<(bc + Grid.boxSize) {
                        units.append(r * Grid.size + c)
                    }
                }
            }
        }
        return units
    }

    /// The cell indices making up one unit.
    public static func cells(inUnit unitIndex: Int) -> [Int] {
        let start = unitIndex * Grid.size
        return Array(flat[start..<(start + Grid.size)])
    }

    /// The 20 cells sharing a row, column or box with `index`, excluding itself.
    public static func peers(of index: Int) -> [Int] {
        let row = index / Grid.size
        let col = index % Grid.size
        var result = Set<Int>()
        for i in 0..<Grid.size {
            result.insert(row * Grid.size + i)
            result.insert(i * Grid.size + col)
        }
        let boxRow = row / Grid.boxSize * Grid.boxSize
        let boxCol = col / Grid.boxSize * Grid.boxSize
        for r in boxRow..<(boxRow + Grid.boxSize) {
            for c in boxCol..<(boxCol + Grid.boxSize) {
                result.insert(r * Grid.size + c)
            }
        }
        result.remove(index)
        return result.sorted()
    }

    /// Reads the flat unit table without copying.
    @inlinable
    public static func withUnsafeUnits<R>(_ body: (UnsafeBufferPointer<Int>) throws -> R) rethrows -> R {
        try flat.withUnsafeBufferPointer(body)
    }
}
