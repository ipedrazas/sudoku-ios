import Foundation
import Testing

@testable import SudokuKit

@Suite("Daily puzzle")
struct DailyPuzzleTests {

    /// The golden set. Generated once, then frozen.
    ///
    /// These are not hand-computed values — they are what the engine produces,
    /// pinned so that any change to the RNG, the shuffle, the carve order or the
    /// difficulty spec fails the build instead of silently rewriting everyone's
    /// daily history. A deliberate change means regenerating this table, which
    /// is exactly the moment someone should stop and think.
    struct Golden {
        let key: String
        let seed: UInt64
        let puzzle: String
        let tier: Int
        let clues: Int

        init(_ key: String, _ seed: UInt64, _ puzzle: String, _ tier: Int, _ clues: Int) {
            self.key = key
            self.seed = seed
            self.puzzle = puzzle
            self.tier = tier
            self.clues = clues
        }
    }

    static let goldens: [Golden] = [
        Golden(
            "2026-01-01", 1_767_225_600,
            "900402870000903001080017000460800309030000000000000087040001005072000906600000700",
            3, 28
        ),
        Golden(
            "2026-08-10", 1_786_320_000,
            "090000030000800070801000005967000400000060002040710063000603000630075080000481000",
            3, 28
        ),
        Golden(
            "2026-12-25", 1_798_156_800,
            "000000000780000504004108260070005413000000020206400007400810000960500000005009700",
            3, 28
        ),
        Golden(
            "2025-02-28", 1_740_700_800,
            "003007000700090060050200000000800000140003800030964710004100006300400200070008501",
            3, 28
        ),
        Golden(
            "2027-06-15", 1_813_017_600,
            "038000060600450310000000400050900248000000100041000009900534000005790800000200500",
            3, 28
        ),
    ]

    @Test("known dates still generate their pinned puzzles")
    func goldenValues() {
        for golden in Self.goldens {
            guard let date = DailyPuzzle.date(fromKey: golden.key) else {
                Issue.record("could not parse \(golden.key)")
                continue
            }

            #expect(DailyPuzzle.seed(for: date) == golden.seed, "seed drifted for \(golden.key)")

            let daily = DailyPuzzle.generate(for: date)
            #expect(
                daily.puzzle.digits() == golden.puzzle,
                """
                the daily for \(golden.key) has changed.

                If this was deliberate, regenerate the golden table — but be sure:
                every player's daily history and streak depends on past dates
                generating the same puzzle they did before.
                """
            )
            #expect(daily.tier.rawValue == golden.tier)
            #expect(daily.clueCount == golden.clues)
        }
    }

    @Test("the same date generates the same puzzle every time")
    func reproducible() {
        guard let date = DailyPuzzle.date(fromKey: "2026-03-03") else { return }
        let first = DailyPuzzle.generate(for: date)
        for _ in 0..<3 {
            #expect(DailyPuzzle.generate(for: date) == first)
        }
    }

    @Test("any time of day maps to the same daily")
    func timeOfDayDoesNotMatter() {
        guard let midnight = DailyPuzzle.date(fromKey: "2026-05-20") else { return }
        let lateEvening = midnight.addingTimeInterval(23 * 3600 + 59 * 60)

        #expect(DailyPuzzle.seed(for: midnight) == DailyPuzzle.seed(for: lateEvening))
        #expect(DailyPuzzle.dateKey(for: lateEvening) == "2026-05-20")
    }

    @Test("consecutive days generate different puzzles")
    func daysAreDistinct() {
        guard let start = DailyPuzzle.date(fromKey: "2026-04-01") else { return }
        var puzzles = Set<String>()
        for offset in 0..<20 {
            let date = start.addingTimeInterval(Double(offset) * 86_400)
            puzzles.insert(DailyPuzzle.generate(for: date).puzzle.digits())
        }
        #expect(puzzles.count == 20, "some dates share a puzzle")
    }

    @Test("date keys round-trip")
    func dateKeyRoundTrip() {
        for key in ["2024-02-29", "2026-01-01", "2026-12-31", "2030-07-04"] {
            guard let date = DailyPuzzle.date(fromKey: key) else {
                Issue.record("could not parse \(key)")
                continue
            }
            #expect(DailyPuzzle.dateKey(for: date) == key)
        }
    }

    @Test("malformed date keys are rejected", arguments: ["", "2026", "2026-01", "not-a-date", "2026/01/01"])
    func rejectsMalformedKeys(key: String) {
        #expect(DailyPuzzle.date(fromKey: key) == nil)
    }

    /// The daily rolls over at UTC midnight so two players in different time
    /// zones are never on different puzzles.
    @Test("keys are computed in UTC, not local time")
    func usesUTC() {
        // Foundation normalises the "UTC" identifier to "GMT", so assert the
        // property that actually matters rather than the label.
        #expect(DailyPuzzle.calendar.timeZone.secondsFromGMT() == 0)

        // 23:30 UTC on the 1st is still the 1st, even where it is already the 2nd.
        guard let date = DailyPuzzle.date(fromKey: "2026-06-01")?.addingTimeInterval(23.5 * 3600) else { return }
        #expect(DailyPuzzle.dateKey(for: date) == "2026-06-01")
    }

    @Test("a date range yields every day inclusive")
    func dateRange() {
        guard let start = DailyPuzzle.date(fromKey: "2026-01-30"),
            let end = DailyPuzzle.date(fromKey: "2026-02-02")
        else { return }

        #expect(
            DailyPuzzle.dateKeys(from: start, to: end)
                == ["2026-01-30", "2026-01-31", "2026-02-01", "2026-02-02"]
        )
    }

    @Test("dailies are solvable by logic and uniquely solvable")
    func dailiesArePlayable() {
        guard let start = DailyPuzzle.date(fromKey: "2026-09-01") else { return }
        for offset in 0..<5 {
            let daily = DailyPuzzle.generate(for: start.addingTimeInterval(Double(offset) * 86_400))
            #expect(Solver.hasUniqueSolution(daily.puzzle))
            #expect(daily.tier < .beyond)
            #expect(Solver.solve(daily.puzzle) == daily.solution)
        }
    }
}
