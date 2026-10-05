/// "Fill in all notes", done the way a player would do it by hand.
///
/// The first version marked every digit the placed numbers allowed. That is
/// correct and not much use: players found themselves going back to cross out
/// digits they had already ruled out, and digits a locked candidate or a pair
/// rules out on sight.
public enum AutoNotes {

    /// The notes to show after filling, as one candidate mask per cell.
    ///
    /// Two rules, in this order:
    ///
    /// 1. **The player's own eliminations stand.** A cell that already has
    ///    notes keeps only those still possible; filling never puts back a
    ///    digit the player crossed out. A cell with no notes gets the full set.
    /// 2. **Then every elimination the engine knows is applied** — locked
    ///    candidates, pairs, triples, X-wings — to a fixpoint. Nothing is
    ///    placed: a cell left with one candidate shows that one.
    ///
    /// The logic runs only while the board agrees with the solution. A wrong
    /// digit on the board makes every deduction from it suspect, and pruning
    /// notes on a false premise can cross out the right answer; on such a
    /// board the fill keeps to rule 1. Likewise notes that have already lost
    /// the solution digit are not reasoned from (see
    /// `CandidateGrid.init(_:notes:solution:)`), though they are still kept —
    /// they are the player's, and the hint is where mistakes get pointed out.
    public static func fill(board: borrowing Grid, notes: [UInt16], solution: borrowing Grid) -> [UInt16] {
        let known = CandidateGrid(board, notes: notes, solution: solution)
        let logic =
            HintEngine.firstMistake(in: board, against: solution) == nil
            ? Rater.eliminations(for: board, knowing: known)
            : known
        let plain = CandidateGrid(board)
        let hasNotes = notes.count == Grid.cellCount

        return (0..<Grid.cellCount).map { index in
            guard board[index] == 0 else { return 0 }
            let own = hasNotes ? notes[index] & plain[index] : 0
            guard own != 0 else { return logic[index] }
            let kept = own & logic[index]
            // Only reachable when the player's notes for this cell are wrong.
            // An empty cell reads as "never filled", which is worse than
            // handing back the candidates the board allows.
            return kept != 0 ? kept : logic[index]
        }
    }
}
