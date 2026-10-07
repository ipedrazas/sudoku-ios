/// "Fill in all notes", done the way a player would do it by hand.
///
/// The first version marked every digit the placed numbers allowed, which
/// left players going back to cross out digits they had already ruled out.
///
/// The second also applied every elimination the engine knows — locked
/// candidates, pairs, triples, X-wings — to a fixpoint. That gave the puzzle
/// away: a cell already down to one candidate counts as a "pair" with any
/// neighbour, so the subset techniques quietly propagate naked and hidden
/// singles, and on most puzzles every note came back as the answer. Deductions
/// are the game; the hint is where the engine offers one, one at a time.
public enum AutoNotes {

    /// The notes to show after filling, as one candidate mask per cell.
    ///
    /// Every digit the placed numbers allow, except that **the player's own
    /// eliminations stand**: a cell that already has notes keeps only those
    /// still possible, so filling never puts back a digit the player crossed
    /// out. A cell with no notes gets the full set. Notes are the player's even
    /// when they have lost the solution digit; the hint is where mistakes get
    /// pointed out.
    public static func fill(board: borrowing Grid, notes: [UInt16]) -> [UInt16] {
        let plain = CandidateGrid(board)
        let hasNotes = notes.count == Grid.cellCount

        return (0..<Grid.cellCount).map { index in
            guard board[index] == 0 else { return 0 }
            let own = hasNotes ? notes[index] & plain[index] : 0
            // An empty cell reads as "never filled", which is worse than
            // handing back the candidates the board allows.
            return own != 0 ? own : plain[index]
        }
    }
}
