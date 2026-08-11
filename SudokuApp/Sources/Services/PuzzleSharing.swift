import Foundation
import SudokuKit

/// Turning a puzzle into something you can send someone, and back again.
///
/// The web app shared a slug the server could resolve. With no server the code
/// *is* the puzzle: `ShareCode` packs the givens into ~46 base64url characters,
/// so a link needs nothing to exist on the other end but the app.
enum PuzzleSharing {

    /// The custom scheme, which works with no infrastructure at all, and is why
    /// sharing ships without waiting on a domain.
    static func url(for puzzle: borrowing SudokuKit.Grid) -> URL? {
        ShareCode.url(for: puzzle)
    }

    /// The `https` form, for anywhere a custom scheme will not survive — mail,
    /// most chat apps. It needs an apple-app-site-association file on the domain
    /// before the OS will route it, and until then it opens the web page.
    static func universalLink(for puzzle: borrowing SudokuKit.Grid) -> URL? {
        ShareCode.universalLink(for: puzzle)
    }

    /// The puzzle in a URL, whichever form it arrived in.
    ///
    /// Both shapes are accepted on the way in regardless of which one we hand
    /// out, because a link outlives the version of the app that made it.
    static func puzzle(from url: URL) -> SudokuKit.Grid? {
        guard let code = ShareCode.code(from: url) else { return nil }
        return try? ShareCode.decode(code)
    }

    /// A shared puzzle, ready to play.
    static func generatedPuzzle(from url: URL) -> GeneratedPuzzle? {
        guard let code = ShareCode.code(from: url) else { return nil }
        return generatedPuzzle(from: code)
    }

    /// The same, from a code already extracted — which is the shape a
    /// `DeepLink` carries, having done the URL parsing once already.
    ///
    /// The solution is computed here, not deferred: hints and mistake detection
    /// are both diffs against it. A code that decodes to a grid with no unique
    /// solution is rejected — the sender may have an older or hand-made code,
    /// and half-importing it would produce a game whose hints lie.
    static func generatedPuzzle(from code: String) -> GeneratedPuzzle? {
        guard let grid = try? ShareCode.decode(code) else { return nil }
        guard Solver.countSolutions(grid, limit: 2) == 1, let solution = Solver.solve(grid) else { return nil }

        let tier = Rater.rate(grid)
        return GeneratedPuzzle(
            puzzle: grid,
            solution: solution,
            difficulty: ImportModel.difficulty(for: tier),
            tier: tier
        )
    }
}
