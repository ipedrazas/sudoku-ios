/// How much of a hint the player has asked for.
///
/// The web app has one hint: the server says what digit goes in a cell. With the
/// technique solver on device, a hint can escalate — and at the first three
/// levels it teaches instead of answering.
public enum HintLevel: Int, Comparable, Sendable, CaseIterable {
    /// Name the technique and roughly where. "There's a hidden single in box 4."
    case nudge
    /// Highlight the unit and the cells involved.
    case locate
    /// Explain the deduction in words.
    case explain
    /// Fill the cell in.
    case reveal

    public static func < (lhs: HintLevel, rhs: HintLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// What this level costs. Escalating on the same cell charges only the
    /// difference, so a player who works up from a nudge is never worse off than
    /// one who jumps straight to the answer.
    public var cost: Int {
        switch self {
        case .nudge: 1
        case .locate: 1
        case .explain: 2
        case .reveal: 3
        }
    }
}

/// A cell whose value contradicts the solution.
public struct Mistake: Equatable, Sendable {
    /// The offending cell.
    public let cell: CellRef
    /// What the solution has there.
    public let expected: Int
    /// What the player entered.
    public let found: Int
}

/// What the engine found when asked for help.
public enum HintOutcome: Equatable, Sendable {
    /// The board contradicts the solution: nothing else is worth saying.
    case mistake(firstWrong: CellRef, expected: Int, found: Int)
    /// A deduction is available.
    case step(TechniqueStep)
    /// The board is complete and correct.
    case solved
    /// No technique in the engine's repertoire applies. Only reachable on an
    /// imported puzzle that needs chains; generated puzzles never get here.
    case stuck
}

/// A hint, and the text for each level of it.
public struct Hint: Equatable, Sendable {
    public let outcome: HintOutcome
    /// Cells to highlight.
    public let cells: [CellRef]
    /// Units to highlight.
    public let units: [UnitRef]
    /// The placement to make, when the player asks to reveal.
    public let placement: (cell: CellRef, digit: Int)?

    public static func == (lhs: Hint, rhs: Hint) -> Bool {
        lhs.outcome == rhs.outcome && lhs.cells == rhs.cells && lhs.units == rhs.units
            && lhs.placement?.cell == rhs.placement?.cell && lhs.placement?.digit == rhs.placement?.digit
    }
}

/// Technique-explaining hints, with exact mistake detection.
public enum HintEngine {

    /// The next hint for a board.
    ///
    /// **Mistakes are checked first, and checked exactly.** Because the solution
    /// is always on hand — generated with the puzzle, or computed at import — a
    /// single pass finds the first cell that contradicts it. That matters more
    /// than it looks: `Rater.rate` reports the easiest possible tier for any
    /// full grid without inspecting it, and every technique hint computed from a
    /// corrupted board is reasoning from a false premise. Telling the player
    /// where they went wrong is both cheaper and more useful than explaining a
    /// deduction that cannot help them.
    public static func hint(for board: borrowing Grid, solution: borrowing Grid) -> Hint {
        if let mistake = firstMistake(in: board, against: solution) {
            return Hint(
                outcome: .mistake(firstWrong: mistake.cell, expected: mistake.expected, found: mistake.found),
                cells: [mistake.cell],
                units: [.row(mistake.cell.row), .column(mistake.cell.col), .box(mistake.cell.box)],
                placement: (mistake.cell, 0)
            )
        }

        if board.isFull {
            return Hint(outcome: .solved, cells: [], units: [], placement: nil)
        }

        guard let step = Rater.nextStep(for: board) else {
            // No technique applies, but the board is correct so far — fall back
            // to the solution for the most constrained empty cell rather than
            // leaving the player with nothing.
            if let fallback = mostConstrainedCell(in: board) {
                return Hint(
                    outcome: .stuck,
                    cells: [fallback],
                    units: [],
                    placement: (fallback, solution[fallback])
                )
            }
            return Hint(outcome: .stuck, cells: [], units: [], placement: nil)
        }

        return Hint(
            outcome: .step(step),
            cells: highlightCells(for: step),
            units: highlightUnits(for: step),
            placement: step.placedCell
        )
    }

    /// The first cell whose value contradicts the solution, scanning in reading
    /// order so the player is sent to the earliest error rather than an
    /// arbitrary one.
    public static func firstMistake(
        in board: borrowing Grid,
        against solution: borrowing Grid
    ) -> Mistake? {
        for index in 0..<Grid.cellCount {
            let value = board[index]
            guard value != 0, value != solution[index] else { continue }
            return Mistake(cell: CellRef(index: index), expected: solution[index], found: value)
        }
        return nil
    }

    /// The empty cell with the fewest candidates — where a stuck player has the
    /// best chance of making progress unaided.
    static func mostConstrainedCell(in board: borrowing Grid) -> CellRef? {
        let candidates = CandidateGrid(board)
        var best: CellRef?
        var bestCount = Grid.size + 1

        for index in 0..<Grid.cellCount where board[index] == 0 {
            let count = Candidates.count(candidates[index])
            if count > 0, count < bestCount {
                best = CellRef(index: index)
                bestCount = count
            }
        }
        return best
    }

    // MARK: - Presentation

    static func highlightCells(for step: TechniqueStep) -> [CellRef] {
        switch step {
        case .nakedSingle(let cell, _): [cell]
        case .hiddenSingle(let cell, _, _): [cell]
        case .lockedCandidate(_, _, _, let eliminates): eliminates
        case .nakedSubset(let cells, _, _, let eliminates): cells + eliminates
        case .hiddenSubset(let cells, _, _): cells
        case .xWing(_, _, let eliminates): eliminates
        }
    }

    static func highlightUnits(for step: TechniqueStep) -> [UnitRef] {
        switch step {
        case .nakedSingle(let cell, _):
            [.row(cell.row), .column(cell.col), .box(cell.box)]
        case .hiddenSingle(_, _, let unit):
            [unit]
        case .lockedCandidate(_, let box, let line, _):
            [.box(box), line]
        case .nakedSubset(_, _, let unit, _):
            [unit]
        case .hiddenSubset(_, _, let unit):
            [unit]
        case .xWing(_, let lines, _):
            lines
        }
    }
}

extension Hint {
    /// The text to show at a given level.
    ///
    /// Levels below `.reveal` deliberately withhold the answer: the point is to
    /// teach the pattern, so the player can find the next one themselves.
    public func text(at level: HintLevel) -> String {
        switch outcome {
        case .mistake(let cell, let expected, let found):
            switch level {
            case .nudge:
                return Copy.text("hint.mistake.nudge")
            case .locate:
                return Copy.text("hint.mistake.locate", cell.description)
            case .explain:
                return Copy.text("hint.mistake.explain", cell.description, found)
            case .reveal:
                return Copy.text("hint.mistake.reveal", cell.description, expected, found)
            }

        case .solved:
            return Copy.text("hint.solved")

        case .stuck:
            switch level {
            case .nudge, .locate, .explain:
                return Copy.text("hint.stuck.teaching")
            case .reveal:
                guard let placement else { return Copy.text("hint.stuck.none") }
                return Copy.text("hint.reveal.placement", placement.cell.description, placement.digit)
            }

        case .step(let step):
            return Self.text(for: step, at: level)
        }
    }

    private static func text(for step: TechniqueStep, at level: HintLevel) -> String {
        switch step {
        case .nakedSingle(let cell, let digit):
            switch level {
            case .nudge: return Copy.text("hint.nakedSingle.nudge")
            case .locate: return Copy.text("hint.nakedSingle.locate", cell.description)
            case .explain:
                // A cell is not a digit. The earlier wording read "R4C2 is the
                // only digit not already in its row, column or box", which is a
                // category error and, worse, describes a different technique.
                return Copy.text("hint.nakedSingle.explain", cell.description)
            case .reveal: return Copy.text("hint.reveal.placement", cell.description, digit)
            }

        case .hiddenSingle(let cell, let digit, let unit):
            switch level {
            case .nudge: return Copy.text("hint.hiddenSingle.nudge", unit.localizedName)
            case .locate: return Copy.text("hint.hiddenSingle.locate", unit.localizedName)
            case .explain:
                return Copy.text("hint.hiddenSingle.explain", cell.description, unit.localizedName, digit)
            case .reveal: return Copy.text("hint.reveal.placement", cell.description, digit)
            }

        case .lockedCandidate(let digit, let box, let line, let eliminates):
            // The box is spelled by the same rule as any other unit, so it picks
            // up its article with everything else rather than being the one
            // place a language has to accept "box 4" bare.
            let boxName = UnitRef.box(box).localizedName
            switch level {
            case .nudge: return Copy.text("hint.lockedCandidate.nudge", boxName)
            case .locate: return Copy.text("hint.lockedCandidate.locate", boxName, digit, line.localizedName)
            case .explain:
                return Copy.text(
                    "hint.lockedCandidate.explain",
                    digit,
                    boxName,
                    line.localizedName,
                    Copy.text("hint.lockedCandidate.otherCells", eliminates.count)
                )
            case .reveal:
                return Copy.text("hint.lockedCandidate.reveal", digit, Copy.list(eliminates.map(\.description)))
            }

        case .nakedSubset(let cells, let digits, let unit, let eliminates):
            let names = Copy.list(cells.map(\.description))
            let digitList = Copy.list(digits.map(String.init))
            switch level {
            case .nudge:
                let key = cells.count == 2 ? "hint.nakedPair.nudge" : "hint.nakedTriple.nudge"
                return Copy.text(key, unit.localizedName)
            case .locate: return Copy.text("hint.nakedSubset.locate", names, unit.localizedName)
            case .explain:
                return Copy.text("hint.nakedSubset.explain", names, digitList, unit.localizedName)
            case .reveal:
                return Copy.text("hint.nakedSubset.reveal", digitList, Copy.list(eliminates.map(\.description)))
            }

        case .hiddenSubset(let cells, let digits, let unit):
            let digitList = Copy.list(digits.map(String.init))
            switch level {
            case .nudge:
                let key = digits.count == 2 ? "hint.hiddenPair.nudge" : "hint.hiddenTriple.nudge"
                return Copy.text(key, unit.localizedName)
            case .locate: return Copy.text("hint.hiddenSubset.locate", unit.localizedName, digitList)
            case .explain:
                return Copy.text("hint.hiddenSubset.explain", digitList, Copy.list(cells.map(\.description)))
            case .reveal:
                return Copy.text("hint.hiddenSubset.reveal", Copy.list(cells.map(\.description)), digitList)
            }

        case .xWing(let digit, let lines, let eliminates):
            let lineList = Copy.list(lines.map(\.localizedName))
            switch level {
            case .nudge: return Copy.text("hint.xWing.nudge", digit)
            case .locate: return Copy.text("hint.xWing.locate", lineList, digit)
            case .explain:
                return Copy.text("hint.xWing.explain", digit, lineList)
            case .reveal:
                return Copy.text("hint.xWing.reveal", digit, Copy.list(eliminates.map(\.description)))
            }
        }
    }
}
