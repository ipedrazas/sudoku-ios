/// A single deduction a human solver could make.
///
/// The Go implementation only ever asks "how hard is this puzzle?", so it
/// discards its reasoning. Keeping the step is what lets hints *teach* rather
/// than just reveal an answer: the web app can only ask the server what digit
/// goes in a cell, whereas here the solver can say why.
public enum TechniqueStep: Equatable, Sendable {
    /// Only one digit fits in this cell.
    case nakedSingle(cell: CellRef, digit: Int)
    /// Only one cell in this unit can hold this digit.
    case hiddenSingle(cell: CellRef, digit: Int, unit: UnitRef)
    /// A digit confined to one line within a box (or one box within a line),
    /// eliminating it elsewhere.
    case lockedCandidate(digit: Int, box: Int, line: UnitRef, eliminates: [CellRef])
    /// k cells sharing exactly k candidates, which no other cell in the unit may use.
    case nakedSubset(cells: [CellRef], digits: [Int], unit: UnitRef, eliminates: [CellRef])
    /// k digits confined to exactly k cells, which may hold nothing else.
    case hiddenSubset(cells: [CellRef], digits: [Int], unit: UnitRef)
    /// A digit forming a rectangle across two lines, eliminating it from the crossing lines.
    case xWing(digit: Int, lines: [UnitRef], eliminates: [CellRef])

    /// The difficulty tier this technique belongs to.
    public var tier: Tier {
        switch self {
        case .nakedSingle: .nakedSingle
        case .hiddenSingle: .hiddenSingle
        case .lockedCandidate, .nakedSubset: .locked
        case .hiddenSubset, .xWing: .advanced
        }
    }

    /// The cell this step fills, if it fills one.
    public var placedCell: (cell: CellRef, digit: Int)? {
        switch self {
        case .nakedSingle(let cell, let digit): (cell, digit)
        case .hiddenSingle(let cell, let digit, _): (cell, digit)
        default: nil
        }
    }

    /// Short technique name, for hint copy and stats.
    public var techniqueName: String {
        switch self {
        case .nakedSingle: "naked single"
        case .hiddenSingle: "hidden single"
        case .lockedCandidate: "locked candidate"
        case .nakedSubset(let cells, _, _, _): cells.count == 2 ? "naked pair" : "naked triple"
        case .hiddenSubset(let cells, _, _): cells.count == 2 ? "hidden pair" : "hidden triple"
        case .xWing: "X-wing"
        }
    }
}
