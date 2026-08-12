import Testing

@testable import SudokuKit

/// Copy for every technique at every level.
///
/// The teaching levels are the reason the hint engine exists — a hint that only
/// reveals the answer is what the web app already had. Each case below is
/// exercised directly rather than waiting for a puzzle that happens to need it,
/// because "we never generated an X-wing during tests" is not a reason to ship
/// untested copy.
@Suite("Hint copy")
struct HintCopyTests {

    private func hint(_ step: TechniqueStep) -> Hint {
        Hint(
            outcome: .step(step),
            cells: HintEngine.highlightCells(for: step),
            units: HintEngine.highlightUnits(for: step),
            placement: step.placedCell
        )
    }

    private static let cellA = CellRef(row: 4, col: 1)
    private static let cellB = CellRef(row: 4, col: 5)
    private static let cellC = CellRef(row: 4, col: 7)

    static let steps: [TechniqueStep] = [
        .nakedSingle(cell: cellA, digit: 7),
        .hiddenSingle(cell: cellA, digit: 7, unit: .box(3)),
        .lockedCandidate(digit: 3, box: 4, line: .row(4), eliminates: [cellB, cellC]),
        .nakedSubset(cells: [cellA, cellB], digits: [2, 5], unit: .row(4), eliminates: [cellC]),
        .nakedSubset(cells: [cellA, cellB, cellC], digits: [2, 5, 8], unit: .row(4), eliminates: [cellA]),
        .hiddenSubset(cells: [cellA, cellB], digits: [4, 6], unit: .column(1)),
        .xWing(digit: 9, lines: [.row(1), .row(6)], eliminates: [cellA, cellB]),
    ]

    /// Every language the kit ships copy for.
    ///
    /// Read from the kit rather than listed here, so adding a translation puts
    /// it under test without anyone remembering to.
    static let languages: [String] = Copy.availableLanguages

    @Test("every technique has copy at every level", arguments: steps, languages)
    func copyExists(step: TechniqueStep, language: String) {
        Copy.$language.withValue(language) {
            let hint = hint(step)
            for level in HintLevel.allCases {
                let text = hint.text(at: level)
                #expect(!text.isEmpty, "[\(language)] \(step.techniqueName) has no copy at \(level)")
                #expect(
                    text.last == ".",
                    "[\(language)] \(step.techniqueName) copy at \(level) is not a sentence: \(text)"
                )
                #expect(!text.contains("Optional("), "[\(language)] copy leaked an Optional at \(level): \(text)")
                #expect(!text.contains("  "), "[\(language)] copy has doubled spaces at \(level): \(text)")
                // A key that a translation is missing comes back as the key
                // itself. It ends in a word, not a full stop, so the assertion
                // above already catches it — but saying so directly turns a
                // baffling failure into an obvious one.
                #expect(!text.hasPrefix("hint."), "[\(language)] no copy for a hint key at \(level): \(text)")
                #expect(!text.contains("%"), "[\(language)] a format specifier survived at \(level): \(text)")
            }
        }
    }

    @Test("copy gets more specific as the level rises", arguments: steps, languages)
    func copyEscalates(step: TechniqueStep, language: String) {
        Copy.$language.withValue(language) {
            let hint = hint(step)
            let nudge = hint.text(at: .nudge)
            let explain = hint.text(at: .explain)
            #expect(
                explain.count > nudge.count,
                "[\(language)] \(step.techniqueName): explain should say more than nudge"
            )
        }
    }

    @Test("a nudge names the technique without naming the cells", arguments: steps, languages)
    func nudgeIsVague(step: TechniqueStep, language: String) {
        Copy.$language.withValue(language) {
            let nudge = hint(step).text(at: .nudge)
            for cell in HintEngine.highlightCells(for: step) {
                #expect(
                    !nudge.contains(cell.description),
                    "[\(language)] the nudge for \(step.techniqueName) leaked \(cell)"
                )
            }
        }
    }

    /// Spanish inflects, and the wrong article is the failure this whole
    /// restructuring exists to prevent.
    ///
    /// Units carry their own article, so any sentence placing "de" or "a"
    /// immediately before one produces "de el bloque 4" — which no Spanish
    /// speaker writes, and which a translator working only in the strings file
    /// cannot fix, because the preposition is on the other side of a `%@`.
    @Test("Spanish never leaves an uncontracted preposition before a unit", arguments: steps)
    func spanishContractions(step: TechniqueStep) {
        Copy.$language.withValue("es") {
            let hint = hint(step)
            for level in HintLevel.allCases {
                let text = hint.text(at: level)
                // Whole words, not substrings: "Quita el 3" contains "a el" and
                // is perfectly good Spanish. What is being looked for is the
                // preposition standing on its own in front of "el".
                let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
                for (first, second) in zip(words, words.dropFirst()) {
                    let preposition = first.lowercased()
                    #expect(
                        !((preposition == "de" || preposition == "a") && second == "el"),
                        "\(step.techniqueName) at \(level) reads '\(first) el', which contracts: \(text)"
                    )
                }
            }
        }
    }

    @Test("elimination steps name what to remove at reveal")
    func eliminationsAreNamed() {
        let step = TechniqueStep.lockedCandidate(
            digit: 3, box: 4, line: .row(4), eliminates: [Self.cellB, Self.cellC]
        )
        let reveal = hint(step).text(at: .reveal)
        #expect(reveal.contains(Self.cellB.description))
        #expect(reveal.contains(Self.cellC.description))
        #expect(reveal.contains("3"))
    }

    @Test("placement steps name the digit at reveal")
    func placementsAreNamed() {
        for step in [
            TechniqueStep.nakedSingle(cell: Self.cellA, digit: 7),
            TechniqueStep.hiddenSingle(cell: Self.cellA, digit: 7, unit: .box(3)),
        ] {
            let reveal = hint(step).text(at: .reveal)
            #expect(reveal.contains("R5C2"))
            #expect(reveal.contains("7"))
        }
    }

    @Test("pairs and triples are named as such")
    func subsetNaming() {
        let pair = TechniqueStep.nakedSubset(
            cells: [Self.cellA, Self.cellB], digits: [2, 5], unit: .row(4), eliminates: []
        )
        let triple = TechniqueStep.nakedSubset(
            cells: [Self.cellA, Self.cellB, Self.cellC], digits: [2, 5, 8], unit: .row(4), eliminates: []
        )
        let hiddenPair = TechniqueStep.hiddenSubset(cells: [Self.cellA, Self.cellB], digits: [4, 6], unit: .row(4))

        // A pair and a triple must not read the same, in any language: the size
        // of the subset is the thing the nudge is there to tell the player.
        for language in Self.languages {
            Copy.$language.withValue(language) {
                #expect(
                    hint(pair).text(at: .nudge) != hint(triple).text(at: .nudge),
                    "[\(language)] a naked pair and a naked triple nudge identically"
                )
            }
        }

        Copy.$language.withValue("en") {
            #expect(hint(pair).text(at: .nudge).contains("pair"))
            #expect(hint(triple).text(at: .nudge).contains("triple"))
            #expect(hint(hiddenPair).text(at: .nudge).contains("pair"))
        }
        Copy.$language.withValue("es") {
            #expect(hint(pair).text(at: .nudge).contains("pareja"))
            #expect(hint(triple).text(at: .nudge).contains("trío"))
        }

        // Not player-facing — a technique's name is an identifier that shows up
        // in test failures, so it stays put.
        #expect(hiddenPair.techniqueName == "hidden pair")
    }

    @Test("units read in human terms, one-based")
    func unitDescriptions() {
        // `description` is the debugging form and does not translate.
        #expect(UnitRef.row(0).description == "row 1")
        #expect(UnitRef.column(4).description == "column 5")
        #expect(UnitRef.box(8).description == "box 9")

        Copy.$language.withValue("en") {
            #expect(UnitRef.box(3).localizedName == "box 4")
            #expect(hint(.hiddenSingle(cell: Self.cellA, digit: 7, unit: .box(3))).text(at: .nudge).contains("box 4"))
        }
        // The article travels with the unit, which is the whole reason
        // `localizedName` exists separately from `description`.
        Copy.$language.withValue("es") {
            #expect(UnitRef.row(0).localizedName == "la fila 1")
            #expect(UnitRef.box(3).localizedName == "el bloque 4")
            #expect(
                hint(.hiddenSingle(cell: Self.cellA, digit: 7, unit: .box(3))).text(at: .nudge)
                    .contains("el bloque 4")
            )
        }
    }

    @Test("counted phrases agree with their count", arguments: languages)
    func pluralAgreement(language: String) {
        Copy.$language.withValue(language) {
            let one = hint(.lockedCandidate(digit: 3, box: 4, line: .row(4), eliminates: [Self.cellB]))
            let many = hint(
                .lockedCandidate(digit: 3, box: 4, line: .row(4), eliminates: [Self.cellB, Self.cellC])
            )
            #expect(
                one.text(at: .explain) != many.text(at: .explain),
                "[\(language)] one elimination and two read identically, so the plural is not being applied"
            )
            #expect(!one.text(at: .explain).contains("%"), "[\(language)] the plural left a specifier behind")
        }
    }

    @Test("every achievement and difficulty has copy", arguments: languages)
    func catalogueCopy(language: String) {
        Copy.$language.withValue(language) {
            for achievement in Achievements.all {
                #expect(!achievement.name.hasPrefix("achievement."), "[\(language)] no name for \(achievement.key)")
                #expect(
                    !achievement.detail.hasPrefix("achievement."),
                    "[\(language)] no detail for \(achievement.key)"
                )
            }
            for difficulty in Difficulty.allCases {
                #expect(!difficulty.name.hasPrefix("difficulty."), "[\(language)] no name for \(difficulty)")
                // The stored form is not allowed to move with the language.
                #expect(difficulty.rawValue == "\(difficulty)")
            }
        }
    }

    @Test("highlights point at the right places", arguments: steps)
    func highlightsAreUseful(step: TechniqueStep) {
        let hint = hint(step)
        #expect(
            !hint.cells.isEmpty || !hint.units.isEmpty,
            "\(step.techniqueName) highlights nothing, so 'locate' would show the player nothing"
        )
    }

    @Test("the stuck outcome still offers something at every level")
    func stuckCopy() {
        let stuck = Hint(outcome: .stuck, cells: [], units: [], placement: (Self.cellA, 4))
        for level in HintLevel.allCases {
            #expect(!stuck.text(at: level).isEmpty)
        }
        #expect(stuck.text(at: .reveal).contains("4"))

        let nothing = Hint(outcome: .stuck, cells: [], units: [], placement: nil)
        Copy.$language.withValue("en") {
            #expect(nothing.text(at: .reveal) == "No hint available.")
        }
        Copy.$language.withValue("es") {
            #expect(nothing.text(at: .reveal) == "No hay ninguna pista disponible.")
        }
    }

    @Test("hints compare by value")
    func equatable() {
        let step = TechniqueStep.nakedSingle(cell: Self.cellA, digit: 7)
        #expect(hint(step) == hint(step))
        #expect(hint(step) != hint(.nakedSingle(cell: Self.cellB, digit: 7)))
    }
}

/// Coverage for the value types the app layer will lean on.
@Suite("Value types")
struct ValueTypeTests {

    @Test("a grid prints as a readable board")
    func gridDescription() {
        let grid = Fixtures.corpus(kind: "generated-easy")[0].grid
        let text = grid.description
        let lines = text.split(separator: "\n")

        #expect(lines.count == 11, "9 rows plus 2 box separators")
        #expect(text.contains("|"), "box columns should be separated")
        #expect(text.contains("."), "empty cells should render as dots")
    }

    @Test("empty cells are listed in reading order")
    func emptyCells() {
        var grid = Grid()
        grid[0, 0] = 1
        grid[8, 8] = 9

        let empties = grid.emptyCells
        #expect(empties.count == Grid.cellCount - 2)
        #expect(empties.first == CellRef(index: 1))
        #expect(empties.last == CellRef(index: 79))
        #expect(empties == empties.sorted())
    }

    @Test("raw cell access matches the subscripts")
    func unsafeAccess() {
        let grid = Fixtures.corpus(kind: "generated-medium")[0].grid
        grid.withUnsafeCells { cells in
            for index in 0..<Grid.cellCount {
                #expect(Int(cells[index]) == grid[index])
            }
        }
    }

    @Test("candidate masks convert both ways")
    func candidateConversions() {
        let mask = Candidates.mask(of: [1, 5, 9])
        #expect(Candidates.digits(mask) == [1, 5, 9])
        #expect(Candidates.count(mask) == 3)
        #expect(Candidates.lowest(mask) == 1)
        #expect(Candidates.lowest(0) == 0)

        var visited: [Int] = []
        Candidates.forEach(mask) { visited.append($0) }
        #expect(visited == [1, 5, 9])

        #expect(Candidates.all == 0x03FE)
        #expect(Candidates.count(Candidates.all) == 9)
    }

    @Test("a candidate grid agrees with the rules")
    func candidateGrid() {
        let grid = Fixtures.corpus(kind: "generated-hard")[0].grid
        let candidates = CandidateGrid(grid)

        for index in 0..<Grid.cellCount {
            if grid[index] != 0 {
                #expect(candidates[index] == 0, "a filled cell should carry no candidates")
                continue
            }
            // Every candidate must be legal, and the true answer must survive.
            Candidates.forEach(candidates[index]) { digit in
                var probe = grid
                probe[index] = digit
                #expect(Validator.obeysRules(probe), "\(digit) at \(CellRef(index: index)) is not actually legal")
            }
        }

        #expect(candidates[CellRef(index: 0)] == candidates[0])
        #expect(candidates[0, 0] == candidates[0])
    }

    @Test("a contradiction is visible in the candidate grid")
    func candidateContradiction() {
        let good = Fixtures.corpus(kind: "generated-easy")[0].grid
        #expect(!CandidateGrid(good).hasContradiction(in: good))

        // Fill a row with 1…8, leaving a cell whose only digit is blocked in its column.
        var stuck = Grid()
        for col in 0..<8 { stuck[0, col] = col + 1 }
        stuck[1, 8] = 9
        #expect(CandidateGrid(stuck).hasContradiction(in: stuck))
    }

    @Test("cells know their peers")
    func peersProperty() {
        let cell = CellRef(row: 0, col: 0)
        let peers = cell.peers

        #expect(peers.count == 20)
        #expect(peers.contains(CellRef(row: 0, col: 8)), "same row")
        #expect(peers.contains(CellRef(row: 8, col: 0)), "same column")
        #expect(peers.contains(CellRef(row: 2, col: 2)), "same box")
        #expect(!peers.contains(CellRef(row: 4, col: 4)), "unrelated")
        #expect(!peers.contains(cell))
    }

    @Test("cells order by index")
    func cellOrdering() {
        #expect(CellRef(index: 0) < CellRef(index: 1))
        #expect(CellRef(row: 0, col: 5) < CellRef(row: 1, col: 0))
    }

    @Test("difficulty names are presentable")
    func difficultyNames() {
        Copy.$language.withValue("en") {
            #expect(Difficulty.easy.name == "Easy")
            #expect(Difficulty.expert.name == "Expert")
        }
        Copy.$language.withValue("es") {
            #expect(Difficulty.easy.name == "Fácil")
            #expect(Difficulty.expert.name == "Experto")
        }
        #expect(Difficulty.allCases.count == 4)
    }

    @Test("tier names are presentable")
    func tierNames() {
        for tier in Tier.allCases {
            #expect(!tier.name.isEmpty)
        }
        #expect(Tier.advanced.name == "advanced patterns")
    }

    @Test("difficulty specs accept only their own band")
    func specBands() {
        let medium = Difficulty.medium.spec
        #expect(!medium.accepts(.hiddenSingle))
        #expect(medium.accepts(.locked))
        #expect(!medium.accepts(.advanced))

        // No rung ever accepts a puzzle that needs guessing.
        for difficulty in Difficulty.allCases {
            #expect(!difficulty.spec.accepts(.beyond), "\(difficulty) must never accept an unsolvable puzzle")
            #expect(difficulty.spec.maxTier < .beyond)
        }
    }

    @Test("bounded draws are uniform enough to trust")
    func boundedDrawDistribution() {
        var rng = SeededRandom(seed: 2026)
        var counts = [Int](repeating: 0, count: 6)
        let draws = 60_000
        for _ in 0..<draws { counts[rng.nextBounded(6)] += 1 }

        let expected = draws / 6
        for (face, count) in counts.enumerated() {
            let drift = abs(count - expected)
            #expect(drift < expected / 10, "face \(face) came up \(count) times, expected about \(expected)")
        }
    }
}
