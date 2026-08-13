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
    /// Every deduction the engine can explain on this position has already been
    /// shown. Carries a cell to hand over instead, so asking for a different
    /// hint is never a dead end.
    case allShown(cell: CellRef, digit: Int)
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
    /// A cell this hint can hand over outright, and always can.
    ///
    /// `placement` is only set by the techniques that *place* a digit; every
    /// elimination technique — locked candidates, subsets, X-wings — leaves it
    /// nil, because "you can rule 4 out of these two cells" fills nothing in.
    /// That is how a player used to end up in front of a hint they did not
    /// understand with no control but *Done*. `answer` is the way out: the
    /// solution digit for a cell involved in this hint, or for the most
    /// constrained empty cell when the hint involves none.
    public let answer: (cell: CellRef, digit: Int)?

    public init(
        outcome: HintOutcome,
        cells: [CellRef],
        units: [UnitRef],
        placement: (cell: CellRef, digit: Int)?,
        answer: (cell: CellRef, digit: Int)? = nil
    ) {
        self.outcome = outcome
        self.cells = cells
        self.units = units
        self.placement = placement
        self.answer = answer
    }

    public static func == (lhs: Hint, rhs: Hint) -> Bool {
        lhs.outcome == rhs.outcome && lhs.cells == rhs.cells && lhs.units == rhs.units
            && lhs.placement?.cell == rhs.placement?.cell && lhs.placement?.digit == rhs.placement?.digit
            && lhs.answer?.cell == rhs.answer?.cell && lhs.answer?.digit == rhs.answer?.digit
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
    /// - Parameter skipping: cells the player has already been shown a hint
    ///   about and did not find useful. Empty — the ordinary case — asks for the
    ///   engine's best hint and behaves exactly as it always has; non-empty asks
    ///   for a *different* one, which is what the "Show me another" control
    ///   sends.
    public static func hint(
        for board: borrowing Grid,
        solution: borrowing Grid,
        skipping seen: Set<CellRef> = []
    ) -> Hint {
        if let mistake = firstMistake(in: board, against: solution) {
            // A mistake outranks `seen`. There is no "different hint" worth
            // giving while the board contradicts itself, and skipping past it
            // would send the player deeper into a position that cannot be
            // solved.
            return Hint(
                outcome: .mistake(firstWrong: mistake.cell, expected: mistake.expected, found: mistake.found),
                cells: [mistake.cell],
                units: [.row(mistake.cell.row), .column(mistake.cell.col), .box(mistake.cell.box)],
                placement: (mistake.cell, 0),
                answer: (mistake.cell, mistake.expected)
            )
        }

        if board.isFull {
            return Hint(outcome: .solved, cells: [], units: [], placement: nil)
        }

        guard let step = step(for: board, skipping: seen) else {
            // Either no technique applies at all, or every one that does has
            // already been shown. Both end the same way: hand over a cell rather
            // than leave the player with nothing.
            guard let fallback = unseenConstrainedCell(in: board, skipping: seen) else {
                return Hint(outcome: .stuck, cells: [], units: [], placement: nil)
            }
            let digit = solution[fallback]
            return Hint(
                outcome: seen.isEmpty ? .stuck : .allShown(cell: fallback, digit: digit),
                cells: [fallback],
                units: [],
                placement: (fallback, digit),
                answer: (fallback, digit)
            )
        }

        return Hint(
            outcome: .step(step),
            cells: highlightCells(for: step),
            units: highlightUnits(for: step),
            placement: step.placedCell,
            answer: answer(for: step, in: board, solution: solution)
        )
    }

    /// The deduction to explain, honouring what the player has already seen.
    ///
    /// With nothing seen this is `Rater.nextStep` unchanged — the rater's order
    /// is the definition of difficulty and the default hint stays exactly what
    /// it was. Only once the player has asked for something different does the
    /// engine look wider, and then it looks *down* first: the alternatives it
    /// offers are singles, because a player who could not follow an X-wing is
    /// not helped by a second X-wing.
    static func step(for board: borrowing Grid, skipping seen: Set<CellRef>) -> TechniqueStep? {
        guard !seen.isEmpty else { return Rater.nextStep(for: board) }

        if let alternative = followableSingles(in: board).first(where: { !isSeen($0, in: seen) }) {
            return alternative
        }
        if let step = Rater.nextStep(for: board), !isSeen(step, in: seen) {
            return step
        }
        return nil
    }

    /// True when a step points at something the player has already been shown.
    static func isSeen(_ step: TechniqueStep, in seen: Set<CellRef>) -> Bool {
        highlightCells(for: step).contains(where: seen.contains)
    }

    /// Every naked and hidden single available on the board, in that order.
    ///
    /// Read-only, and deliberately so. `TechniqueSolver` finds its steps while
    /// applying them, so the second single it reports may only *be* a single
    /// because the first was placed — true of the solver's board, false of the
    /// player's. Everything here is computed from one candidate snapshot, so
    /// every step returned holds against the board as it stands.
    ///
    /// Singles only, because these are the two techniques that can be acted on
    /// without understanding them: "this cell can only be a 4" needs no theory.
    static func followableSingles(in board: borrowing Grid) -> [TechniqueStep] {
        let candidates = CandidateGrid(board)
        var steps: [TechniqueStep] = []
        var claimed = Set<Int>()

        for index in 0..<Grid.cellCount where board[index] == 0 {
            let mask = candidates[index]
            guard Candidates.count(mask) == 1 else { continue }
            steps.append(.nakedSingle(cell: CellRef(index: index), digit: Candidates.lowest(mask)))
            claimed.insert(index)
        }

        for unitIndex in 0..<Units.count {
            let cells = Units.cells(inUnit: unitIndex)
            for digit in 1...Grid.size {
                let bit = Candidates.bit(digit)
                var home: Int?
                var count = 0
                for index in cells where board[index] == 0 && candidates[index] & bit != 0 {
                    home = index
                    count += 1
                }
                // A digit already placed in the unit is stripped from every
                // candidate in it, so it arrives here with a count of zero.
                guard count == 1, let home, !claimed.contains(home) else { continue }
                steps.append(
                    .hiddenSingle(cell: CellRef(index: home), digit: digit, unit: UnitRef(unitIndex: unitIndex))
                )
                claimed.insert(home)
            }
        }

        return steps
    }

    /// The cell this step's hint can hand over. The cell the step fills when it
    /// fills one; otherwise the tightest empty cell it touches, so "just fill
    /// one in" lands somewhere the hint was actually talking about.
    static func answer(
        for step: TechniqueStep,
        in board: borrowing Grid,
        solution: borrowing Grid
    ) -> (cell: CellRef, digit: Int)? {
        if let placed = step.placedCell { return placed }

        let candidates = CandidateGrid(board)
        let touched = highlightCells(for: step)
            .filter { board[$0.index] == 0 }
            .min { Candidates.count(candidates[$0]) < Candidates.count(candidates[$1]) }

        guard let cell = touched ?? mostConstrainedCell(in: board) else { return nil }
        return (cell, solution[cell])
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

    /// The tightest empty cell the player has not already been sent to, falling
    /// back to the tightest of all rather than to nothing: running out of fresh
    /// cells is not a reason to run out of help.
    static func unseenConstrainedCell(in board: borrowing Grid, skipping seen: Set<CellRef>) -> CellRef? {
        let candidates = CandidateGrid(board)
        var best: CellRef?
        var bestCount = Grid.size + 1

        for index in 0..<Grid.cellCount where board[index] == 0 {
            let cell = CellRef(index: index)
            guard !seen.contains(cell) else { continue }
            let count = Candidates.count(candidates[index])
            if count > 0, count < bestCount {
                best = cell
                bestCount = count
            }
        }
        return best ?? mostConstrainedCell(in: board)
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

        case .allShown(let cell, let digit):
            // Not an apology and not a dead end: the sentence says the engine is
            // out of *explanations*, and the offer of a digit stands at every
            // level rather than only at the last one.
            switch level {
            case .nudge, .locate, .explain:
                return Copy.text("hint.allShown.offer", cell.description)
            case .reveal:
                return Copy.text("hint.reveal.placement", cell.description, digit)
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
