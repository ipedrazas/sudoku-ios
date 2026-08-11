import Foundation
import SudokuKit
import Testing

@testable import SudokuApp

/// Import, sharing, hint presentation and settings.
///
/// The engine's share codec and hint engine are tested in the package. What is
/// tested here is the app's use of them: what the import screen decides, what a
/// link turns back into, what the board lights up, and what a session inherits.
@Suite("Import, sharing and settings")
@MainActor
struct ImportAndSharingTests {

    private func puzzle(_ difficulty: Difficulty = .easy, seed: UInt64 = 1) -> GeneratedPuzzle {
        var rng = SeededRandom(seed: seed)
        return Generator.generate(difficulty, using: &rng)
    }

    // MARK: - Import

    @Test("an empty grid is short of clues, and says how short")
    func emptyImport() {
        let model = ImportModel()
        #expect(model.status == .tooFewClues(clues: 0))
        #expect(!model.status.isReady)
        #expect(model.generatedPuzzle() == nil)
    }

    @Test("a repeated digit is caught before anything is asked of the solver")
    func rulesFirst() throws {
        let model = ImportModel()
        model.select(CellRef(index: 0))
        model.input(5)
        model.select(CellRef(index: 1))
        model.input(5)

        #expect(model.status == .breaksRules)
        #expect(model.conflicts == [CellRef(index: 0), CellRef(index: 1)])
    }

    @Test("a real puzzle imports, and comes back rated")
    func importsAGeneratedPuzzle() throws {
        let generated = puzzle(.medium, seed: 3)
        let model = ImportModel()
        #expect(model.paste(generated.puzzle.digits()))

        guard case .ready(let tier, let clues) = model.status else {
            Issue.record("expected a ready puzzle, got \(model.status)")
            return
        }
        #expect(tier == generated.tier)
        #expect(clues == generated.puzzle.clueCount)

        // And it comes out playable, with the solution the engine needs for
        // hints and mistake detection.
        let imported = try #require(model.generatedPuzzle())
        #expect(imported.puzzle == generated.puzzle)
        #expect(imported.solution == generated.solution)
        #expect(Validator.isSolved(imported.solution))
    }

    @Test("a puzzle with more than one solution is refused")
    func rejectsAmbiguous() throws {
        // A generated puzzle with clues removed until it stops being unique.
        let generated = puzzle(.easy, seed: 5)
        let model = ImportModel()
        #expect(model.paste(generated.puzzle.digits()))
        #expect(model.status.isReady)

        // Strip clues one at a time; a puzzle that has lost its uniqueness
        // reports it rather than quietly accepting a family of grids.
        var digits = Array(generated.puzzle.digits())
        for index in digits.indices where digits[index] != "0" {
            digits[index] = "0"
            _ = model.paste(String(digits))
            if model.status == .notUnique { break }
        }

        #expect(model.status == .notUnique)
        #expect(model.generatedPuzzle() == nil)
    }

    @Test("a grid that obeys the rules but cannot be completed is refused")
    func rejectsUnsolvable() throws {
        // Built rather than hand-written: take a real puzzle and change one
        // given to a digit that breaks no rule in its own row, column or box,
        // until the result is legal-looking and impossible. Searching for the
        // case keeps the test deterministic without hand-deriving a grid.
        let generated = puzzle(.easy, seed: 9)
        var broken: SudokuKit.Grid?

        search: for index in 0..<SudokuKit.Grid.cellCount where generated.puzzle[index] != 0 {
            for digit in 1...9 where digit != generated.puzzle[index] {
                var candidate = generated.puzzle
                candidate[index] = digit
                guard Validator.obeysRules(candidate) else { continue }
                if Solver.countSolutions(candidate, limit: 2) == 0 {
                    broken = candidate
                    break search
                }
            }
        }

        let grid = try #require(broken, "a mistyped given should be able to make a puzzle impossible")
        let model = ImportModel()
        #expect(model.paste(grid.digits()))
        #expect(model.status == .unsolvable)
        #expect(model.generatedPuzzle() == nil)
    }

    @Test("paste ignores anything that is not a grid")
    func pasteRejectsJunk() {
        let model = ImportModel()
        #expect(!model.paste("hello"))
        #expect(!model.paste(String(repeating: "1", count: 80)))
        #expect(model.grid.isEmpty, "a rejected paste leaves the grid alone")
    }

    @Test("every tier maps onto a rung, and describes itself")
    func ratingVocabulary() {
        for tier in Tier.allCases {
            #expect(!ImportModel.describe(tier).isEmpty)
        }
        #expect(ImportModel.difficulty(for: .nakedSingle) == .easy)
        #expect(ImportModel.difficulty(for: .locked) == .medium)
        #expect(ImportModel.difficulty(for: .advanced) == .hard)
        // Beyond the engine's repertoire still has to be playable.
        #expect(ImportModel.difficulty(for: .beyond) == .expert)
    }

    // MARK: - Sharing

    @Test("a shared link round-trips to the same puzzle")
    func shareRoundTrip() throws {
        let generated = puzzle(.hard, seed: 7)
        let url = try #require(PuzzleSharing.url(for: generated.puzzle))

        #expect(url.scheme == "sudokuandcake")
        let decoded = try #require(PuzzleSharing.puzzle(from: url))
        #expect(decoded == generated.puzzle)
    }

    @Test("the universal link decodes too, whichever form was handed out")
    func universalLinkRoundTrip() throws {
        let generated = puzzle(.medium, seed: 11)
        let url = try #require(PuzzleSharing.universalLink(for: generated.puzzle))

        #expect(url.scheme == "https")
        #expect(PuzzleSharing.puzzle(from: url) == generated.puzzle)
    }

    @Test("an opened link arrives ready to play, solution and all")
    func openedLinkIsPlayable() throws {
        let generated = puzzle(.expert, seed: 13)
        let url = try #require(PuzzleSharing.url(for: generated.puzzle))

        let opened = try #require(PuzzleSharing.generatedPuzzle(from: url))
        #expect(opened.puzzle == generated.puzzle)
        #expect(opened.solution == generated.solution)
        #expect(opened.tier == generated.tier)
    }

    @Test("a link that is not one of ours opens nothing")
    func rejectsForeignLinks() throws {
        for string in [
            "https://example.com/p/abc",
            "sudokuandcake://elsewhere/abc",
            "sudokuandcake://p/not-a-code",
            "https://sudoku.ios.andcake.dev/",
        ] {
            let url = try #require(URL(string: string))
            #expect(PuzzleSharing.generatedPuzzle(from: url) == nil, "\(string) should not open a puzzle")
        }
    }

    // MARK: - Hint presentation

    @Test("a hint lights up the cells it is about, and stops when the board moves")
    func hintHighlighting() throws {
        let session = GameSession(puzzle: puzzle())
        let hint = session.hint(at: .nudge)
        session.show(hint)

        #expect(!session.hintCells.isEmpty)
        #expect(session.hintCells == Set(hint.cells))
        #expect(session.hintUnitCells == Set(hint.units.flatMap(\.cells)))

        // The next move makes the hint historical, so it stops being shown.
        let cell = try #require(session.board.emptyCells.first)
        session.select(cell)
        session.input(session.puzzle.solution[cell])
        #expect(session.hintCells.isEmpty)
        #expect(session.activeHint == nil)
    }

    @Test("revealing a mistake erases it rather than doing nothing")
    func revealErasesAMistake() throws {
        let session = GameSession(puzzle: puzzle())
        let cell = try #require(session.board.emptyCells.first)
        let wrong = (1...9).first { $0 != session.puzzle.solution[cell] } ?? 1

        session.select(cell)
        session.input(wrong)
        #expect(session.board[cell] == wrong)

        let hint = session.hint(at: .reveal)
        guard case .mistake(let firstWrong, _, let found) = hint.outcome else {
            Issue.record("a wrong digit should produce a mistake hint, got \(hint.outcome)")
            return
        }
        #expect(firstWrong == cell)
        #expect(found == wrong)

        // The placement is digit 0 — "this should not say what it says" — and
        // acting on it has to clear the cell.
        session.applyHint(hint)
        #expect(session.board[cell] == 0)
    }

    @Test("revealing a technique hint places its digit")
    func revealPlacesADigit() throws {
        let session = GameSession(puzzle: puzzle())
        let hint = session.hint(at: .reveal)

        let placement = try #require(hint.placement)
        #expect(placement.digit != 0)
        session.applyHint(hint)
        #expect(session.board[placement.cell] == placement.digit)
        #expect(session.board[placement.cell] == session.puzzle.solution[placement.cell])
    }

    @Test("every hint level has something to say")
    func hintCopyExists() throws {
        let session = GameSession(puzzle: puzzle(.expert, seed: 4))
        let hint = session.hint(at: .nudge)
        for level in HintLevel.allCases {
            #expect(!hint.text(at: level).isEmpty, "\(level) should have copy")
        }
    }

    // MARK: - Settings

    private func settings() throws -> AppSettings {
        let suite = try #require(UserDefaults(suiteName: "settings.test.\(UUID().uuidString)"))
        return AppSettings(defaults: suite)
    }

    @Test("the defaults match the web app, including the surprising one")
    func settingsDefaults() throws {
        let settings = try settings()

        // Off, on purpose: highlighting mistakes as they happen turns the puzzle
        // into a different game.
        #expect(!settings.highlightsMistakes)
        #expect(settings.inputMode == .cellFirst)
        #expect(settings.inactivityMinutes == 5)
        #expect(!settings.autoFillNotes)
        #expect(settings.hapticsEnabled)
        #expect(!settings.soundEnabled)
        #expect(settings.theme == .system)
        #expect(!settings.reminderEnabled)
        #expect(settings.reminderHour == 19)
    }

    @Test("settings survive a relaunch")
    func settingsPersist() throws {
        let name = "settings.test.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))

        let settings = AppSettings(defaults: suite)
        settings.highlightsMistakes = true
        settings.inputMode = .digitFirst
        settings.inactivityMinutes = 10
        settings.theme = .dark
        settings.reminderHour = 21

        let relaunched = AppSettings(defaults: suite)
        #expect(relaunched.highlightsMistakes)
        #expect(relaunched.inputMode == .digitFirst)
        #expect(relaunched.inactivityMinutes == 10)
        #expect(relaunched.theme == .dark)
        #expect(relaunched.reminderHour == 21)
    }

    @Test("the reminder keys are the ones Phase 5 already wrote")
    func reminderKeysAreUnchanged() throws {
        let name = "settings.test.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))
        // Written by the Phase 5 daily screen, which used @AppStorage directly.
        suite.set(true, forKey: "dailyReminderEnabled")
        suite.set(22, forKey: "dailyReminderHour")

        let settings = AppSettings(defaults: suite)
        #expect(settings.reminderEnabled, "an upgrade must not silently switch the reminder off")
        #expect(settings.reminderHour == 22)
    }

    @Test("erasing everything empties the store and drops the game being played")
    func eraseEverything() throws {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(10))

        let session = library.start(puzzle())
        let cell = try #require(session.board.emptyCells.first)
        session.select(cell)
        session.input(session.puzzle.solution[cell])
        library.flush()
        #expect(library.savedGames.count == 1)

        library.eraseEverything()

        #expect(library.savedGames.isEmpty)
        #expect(try repository.savedGames().isEmpty)
        #expect(try repository.completions().isEmpty)

        // The detached session keeps working but no longer writes: an erase that
        // the next keystroke undoes is not an erase.
        session.select(cell)
        session.erase()
        library.flush()
        #expect(try repository.savedGames().isEmpty)
    }
}
