/// Row/column/box rule checking.
///
/// Port of `backend/internal/validator/validator.go`.
public enum Validator {
    /// The outcome of validating a grid.
    public struct Result: Equatable, Sendable {
        /// No digit appears twice in any row, column or box.
        public let isValid: Bool
        /// Valid *and* every cell filled.
        public let isComplete: Bool

        public init(isValid: Bool, isComplete: Bool) {
            self.isValid = isValid
            self.isComplete = isComplete
        }
    }

    /// Checks the grid for duplicates and whether it is fully filled.
    ///
    /// Note `isComplete` requires `isValid`, matching the Go semantics
    /// (`validator.go:33-36`): a full grid with a duplicate is not "complete",
    /// it is wrong.
    public static func validate(_ grid: borrowing Grid) -> Result {
        let valid = obeysRules(grid)
        return Result(isValid: valid, isComplete: valid && grid.isFull)
    }

    /// True when no digit repeats within any of the 27 units.
    public static func obeysRules(_ grid: borrowing Grid) -> Bool {
        grid.withUnsafeCells { cells in
            Units.withUnsafeUnits { units in
                for unitIndex in 0..<Units.count {
                    var seen: UInt16 = 0
                    let base = unitIndex * Grid.size
                    for offset in 0..<Grid.size {
                        let value = cells[units[base + offset]]
                        if value == 0 { continue }
                        let bit = UInt16(1) << UInt16(value)
                        if seen & bit != 0 { return false }
                        seen |= bit
                    }
                }
                return true
            }
        }
    }

    /// Cells that duplicate another value in the same row, column or box.
    ///
    /// Both halves of a duplicate pair are reported, including a given as the
    /// partner — this mirrors the web app's conflict highlighting
    /// (`frontend/src/hooks/useGameBoard.ts:468-500`), where the point is to show
    /// the user *why* a cell is wrong, not just which cell they typed.
    public static func conflicts(in grid: borrowing Grid) -> Set<CellRef> {
        var result = Set<CellRef>()
        grid.withUnsafeCells { cells in
            Units.withUnsafeUnits { units in
                for unitIndex in 0..<Units.count {
                    let base = unitIndex * Grid.size
                    for first in 0..<Grid.size {
                        let firstIndex = units[base + first]
                        let value = cells[firstIndex]
                        if value == 0 { continue }
                        for second in (first + 1)..<Grid.size {
                            let secondIndex = units[base + second]
                            if cells[secondIndex] == value {
                                result.insert(CellRef(index: firstIndex))
                                result.insert(CellRef(index: secondIndex))
                            }
                        }
                    }
                }
            }
        }
        return result
    }

    /// True when the grid is a complete, correct solution.
    ///
    /// Computed locally so a solve registers with no server and no network —
    /// the web app does the same (`useGameBoard.ts:78-81`).
    public static func isSolved(_ grid: borrowing Grid) -> Bool {
        validate(grid).isComplete
    }
}
