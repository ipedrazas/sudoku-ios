/// A reference to one of the 81 cells.
///
/// The engine's hot paths use bare `Int` indices; `CellRef` is the currency of
/// the public API — hints, conflicts, highlights — where clarity matters more
/// than the last few nanoseconds.
public struct CellRef: Equatable, Hashable, Sendable, Comparable {
    /// 0…80, row-major.
    public let index: Int

    public init(index: Int) {
        precondition((0..<Grid.cellCount).contains(index), "cell index out of range: \(index)")
        self.index = index
    }

    public init(row: Int, col: Int) {
        self.init(index: row * Grid.size + col)
    }

    @inlinable public var row: Int { index / Grid.size }
    @inlinable public var col: Int { index % Grid.size }
    /// Box number, 0…8, reading left-to-right then top-to-bottom.
    @inlinable public var box: Int { (row / Grid.boxSize) * Grid.boxSize + col / Grid.boxSize }

    /// The 20 cells sharing a row, column or box with this one.
    public var peers: [CellRef] {
        Units.peers(of: index).map(CellRef.init(index:))
    }

    public static func < (lhs: CellRef, rhs: CellRef) -> Bool { lhs.index < rhs.index }
}

extension CellRef: CustomStringConvertible {
    /// Standard Sudoku notation, 1-based: R5C2.
    public var description: String { "R\(row + 1)C\(col + 1)" }
}

/// One of the 27 units a Sudoku digit must appear in exactly once.
public enum UnitRef: Equatable, Hashable, Sendable {
    case row(Int)
    case column(Int)
    case box(Int)

    /// Index into `Units.all`, 0…26: rows, then columns, then boxes.
    public var unitIndex: Int {
        switch self {
        case .row(let index): index
        case .column(let index): Grid.size + index
        case .box(let index): Grid.size * 2 + index
        }
    }

    public init(unitIndex: Int) {
        switch unitIndex {
        case 0..<Grid.size: self = .row(unitIndex)
        case Grid.size..<(Grid.size * 2): self = .column(unitIndex - Grid.size)
        default: self = .box(unitIndex - Grid.size * 2)
        }
    }

    public var cells: [CellRef] {
        Units.cells(inUnit: unitIndex).map(CellRef.init(index:))
    }
}

extension UnitRef: CustomStringConvertible {
    public var description: String {
        switch self {
        case .row(let index): "row \(index + 1)"
        case .column(let index): "column \(index + 1)"
        case .box(let index): "box \(index + 1)"
        }
    }
}
