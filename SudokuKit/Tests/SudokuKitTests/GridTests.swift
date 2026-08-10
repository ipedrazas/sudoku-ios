import Testing

@testable import SudokuKit

@Suite("Grid")
struct GridTests {

    @Test("an empty grid has no clues")
    func emptyGrid() {
        let grid = Grid()
        #expect(grid.clueCount == 0)
        #expect(grid.isEmpty)
        #expect(!grid.isFull)
        #expect(grid.emptyCells.count == Grid.cellCount)
    }

    @Test("digits() round-trips through init(digits:)")
    func digitsRoundTrip() {
        for entry in Fixtures.corpus {
            let grid = entry.grid
            #expect(grid.digits() == entry.puzzle)
            #expect(Grid(digits: grid.digits()) == grid)
        }
    }

    @Test("dots and zeros both mean empty")
    func dotsParseAsEmpty() {
        let zeros = String(repeating: "0", count: Grid.cellCount)
        let dots = String(repeating: ".", count: Grid.cellCount)
        #expect(Grid(digits: dots) == Grid(digits: zeros))
        #expect(Grid(digits: dots) == Grid())
    }

    @Test(
        "malformed input is rejected",
        arguments: [
            "",
            "123",
            String(repeating: "0", count: 80),
            String(repeating: "0", count: 82),
            String(repeating: "x", count: 81),
        ]
    )
    func rejectsMalformedInput(text: String) {
        #expect(Grid(digits: text) == nil)
    }

    @Test("values outside 0...9 are rejected")
    func rejectsOutOfRangeValues() {
        var values = [Int](repeating: 0, count: Grid.cellCount)
        values[0] = 10
        #expect(Grid(values: values) == nil)

        values[0] = -1
        #expect(Grid(values: values) == nil)

        // Wrong length, all values individually legal.
        #expect(Grid(values: [Int](repeating: 1, count: 80)) == nil)
    }

    @Test("subscripts address the same cell three ways")
    func subscriptsAgree() {
        var grid = Grid()
        grid[4, 2] = 7

        #expect(grid[4, 2] == 7)
        #expect(grid[4 * Grid.size + 2] == 7)
        #expect(grid[CellRef(row: 4, col: 2)] == 7)
        #expect(grid.clueCount == 1)
    }

    @Test("clue count matches the fixture's own count")
    func clueCountMatchesFixture() {
        for entry in Fixtures.corpus {
            #expect(entry.grid.clueCount == entry.clues)
        }
    }
}

@Suite("CellRef and units")
struct CellRefTests {

    @Test("row, column and box derive from the index")
    func coordinates() {
        let cell = CellRef(index: 40)  // R5C5, centre
        #expect(cell.row == 4)
        #expect(cell.col == 4)
        #expect(cell.box == 4)
        #expect(cell.description == "R5C5")

        #expect(CellRef(index: 0).box == 0)
        #expect(CellRef(index: 8).box == 2)
        #expect(CellRef(index: 72).box == 6)
        #expect(CellRef(index: 80).box == 8)
    }

    @Test("every cell has exactly 20 peers, and peering is symmetric")
    func peers() {
        for index in 0..<Grid.cellCount {
            let peers = Units.peers(of: index)
            #expect(peers.count == 20)
            #expect(!peers.contains(index))
            for peer in peers {
                #expect(Units.peers(of: peer).contains(index), "peering is not symmetric: \(index) / \(peer)")
            }
        }
    }

    @Test("there are 27 units of 9 cells, each cell in exactly 3")
    func unitStructure() {
        #expect(Units.count == 27)
        #expect(Units.flat.count == 27 * Grid.size)

        var membership = [Int](repeating: 0, count: Grid.cellCount)
        for unitIndex in 0..<Units.count {
            let cells = Units.cells(inUnit: unitIndex)
            #expect(Set(cells).count == Grid.size, "unit \(unitIndex) repeats a cell")
            for cell in cells { membership[cell] += 1 }
        }
        #expect(membership.allSatisfy { $0 == 3 }, "every cell belongs to exactly one row, column and box")
    }

    /// The unit ordering is load-bearing: `Rater` walks units in this order, and
    /// changing it changes which technique fires first and therefore the tier.
    @Test("unit ordering is rows, then columns, then boxes")
    func unitOrdering() {
        #expect(UnitRef(unitIndex: 0) == .row(0))
        #expect(UnitRef(unitIndex: 8) == .row(8))
        #expect(UnitRef(unitIndex: 9) == .column(0))
        #expect(UnitRef(unitIndex: 17) == .column(8))
        #expect(UnitRef(unitIndex: 18) == .box(0))
        #expect(UnitRef(unitIndex: 26) == .box(8))

        for unitIndex in 0..<Units.count {
            #expect(UnitRef(unitIndex: unitIndex).unitIndex == unitIndex)
        }

        // Row 0 is the first nine cell indices; box 0 is the top-left 3×3.
        #expect(Units.cells(inUnit: 0) == Array(0..<9))
        #expect(Units.cells(inUnit: 18) == [0, 1, 2, 9, 10, 11, 18, 19, 20])
    }

    @Test("UnitRef.cells agrees with the flat table")
    func unitRefCells() {
        for unitIndex in 0..<Units.count {
            let viaRef = UnitRef(unitIndex: unitIndex).cells.map(\.index)
            #expect(viaRef == Units.cells(inUnit: unitIndex))
        }
    }
}
