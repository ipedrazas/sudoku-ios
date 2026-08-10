/// A 9×9 Sudoku grid. `0` means empty; digits are 1…9.
///
/// Go's `generator.Grid` is `[9][9]int`, a fixed-size array that copies by value
/// for free. Swift has no free equivalent that also back-deploys cleanly, so
/// this wraps a flat 81-element `ContiguousArray` (row-major) and the hot paths
/// take it `borrowing` and work on raw buffers rather than copying it. Carving a
/// puzzle copies the grid thousands of times, so that discipline is the
/// difference between a fast generator and a spinner on "New game".
public struct Grid: Equatable, Hashable, Sendable {
    /// Cells per row/column.
    public static let size = 9
    /// Cells per box edge.
    public static let boxSize = 3
    /// Total cells.
    public static let cellCount = size * size

    @usableFromInline internal var cells: ContiguousArray<UInt8>

    /// An empty grid.
    public init() {
        cells = ContiguousArray(repeating: 0, count: Self.cellCount)
    }

    /// Builds a grid from 81 row-major values. Returns nil unless every value is 0…9.
    public init?(values: some Sequence<Int>) {
        var storage = ContiguousArray<UInt8>()
        storage.reserveCapacity(Self.cellCount)
        for value in values {
            guard (0...Self.size).contains(value) else { return nil }
            storage.append(UInt8(value))
        }
        guard storage.count == Self.cellCount else { return nil }
        cells = storage
    }

    /// Parses an 81-character string. `0` and `.` both mean empty.
    ///
    /// This is the canonical interchange form: it is what the cross-check
    /// fixture stores, what `ShareCode` decodes into, and what test cases are
    /// written in.
    public init?(digits: String) {
        var storage = ContiguousArray<UInt8>()
        storage.reserveCapacity(Self.cellCount)
        for character in digits {
            switch character {
            case ".", "0": storage.append(0)
            case "1"..."9": storage.append(UInt8(character.wholeNumberValue ?? 0))
            default: return nil
            }
        }
        guard storage.count == Self.cellCount else { return nil }
        cells = storage
    }

    @inlinable
    public subscript(row: Int, col: Int) -> Int {
        get { Int(cells[row * Self.size + col]) }
        set { cells[row * Self.size + col] = UInt8(newValue) }
    }

    @inlinable
    public subscript(index: Int) -> Int {
        get { Int(cells[index]) }
        set { cells[index] = UInt8(newValue) }
    }

    @inlinable
    public subscript(cell: CellRef) -> Int {
        get { Int(cells[cell.index]) }
        set { cells[cell.index] = UInt8(newValue) }
    }

    /// Number of filled cells.
    public var clueCount: Int {
        cells.reduce(into: 0) { count, value in count += value == 0 ? 0 : 1 }
    }

    public var isFull: Bool {
        !cells.contains(0)
    }

    public var isEmpty: Bool {
        cells.allSatisfy { $0 == 0 }
    }

    /// Indices of every empty cell, ascending.
    public var emptyCells: [CellRef] {
        (0..<Self.cellCount).compactMap { cells[$0] == 0 ? CellRef(index: $0) : nil }
    }

    /// The canonical 81-character form, using `0` for empty.
    public func digits() -> String {
        String(cells.map { Character(UnicodeScalar(UInt8(ascii: "0") + $0)) })
    }

    /// Reads the raw cells without copying. Used by the solver and rater.
    @inlinable
    public func withUnsafeCells<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        try cells.withUnsafeBufferPointer(body)
    }

    @inlinable
    internal mutating func withUnsafeMutableCells<R>(
        _ body: (inout UnsafeMutableBufferPointer<UInt8>) throws -> R
    ) rethrows -> R {
        try cells.withUnsafeMutableBufferPointer(body)
    }
}

extension Grid: CustomStringConvertible {
    /// A human-readable grid, for test failure output.
    public var description: String {
        var lines: [String] = []
        for row in 0..<Self.size {
            if row % Self.boxSize == 0, row > 0 {
                lines.append("------+-------+------")
            }
            var parts: [String] = []
            for col in 0..<Self.size {
                if col % Self.boxSize == 0, col > 0 { parts.append("|") }
                let value = self[row, col]
                parts.append(value == 0 ? "." : String(value))
            }
            lines.append(parts.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
