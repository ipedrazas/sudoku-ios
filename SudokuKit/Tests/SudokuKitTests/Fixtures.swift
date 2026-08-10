import Foundation

@testable import SudokuKit

/// One entry of the Go↔Swift cross-check corpus.
///
/// Produced by `tools/export-fixtures`, which rates each puzzle with the Go
/// implementation this package is ported from and counts its solutions with an
/// independent Go backtracker.
struct CorpusEntry: Decodable, Sendable {
    let puzzle: String
    let tier: Int
    let solutions: Int
    let clues: Int
    /// Provenance, so a failure says which family of puzzle broke.
    let kind: String

    var grid: Grid {
        guard let grid = Grid(digits: puzzle) else {
            fatalError("corpus entry is not a valid 81-character grid: \(puzzle)")
        }
        return grid
    }

    var expectedTier: Tier {
        guard let tier = Tier(rawValue: tier) else {
            fatalError("corpus entry has an unknown tier \(tier)")
        }
        return tier
    }
}

enum Fixtures {
    /// The full cross-check corpus.
    static let corpus: [CorpusEntry] = load("tier-corpus")

    /// Entries of one provenance, e.g. "generated-hard".
    static func corpus(kind: String) -> [CorpusEntry] {
        corpus.filter { $0.kind == kind }
    }

    /// The single entry of a one-off kind, e.g. "solved-grid".
    static func single(kind: String) -> CorpusEntry {
        guard let entry = corpus.first(where: { $0.kind == kind }) else {
            fatalError("no corpus entry of kind '\(kind)' — regenerate with `task fixtures`")
        }
        return entry
    }

    private static func load(_ name: String) -> [CorpusEntry] {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures"
            )
        else {
            fatalError("missing fixture \(name).json — run `task fixtures`")
        }
        do {
            return try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: url))
        } catch {
            fatalError("could not decode \(name).json: \(error)")
        }
    }
}
