import Foundation
import Testing

@testable import SudokuKit

/// Generation performance, measured against the Go implementation's baseline.
///
/// This is Gate G1 from `plans/implementation-plan.md`: catch a slow port on the
/// command line, before any UI exists and before a device is involved. Carving
/// runs `countSolutions` and `rate` once per removal attempt, so a careless
/// allocation in the inner loop turns "New game" into a spinner.
///
/// Go baseline on an Apple M5 (40 samples per difficulty, `Generate` end to end,
/// retries included):
///
/// | difficulty | p50     | p90     | max     |
/// |------------|---------|---------|---------|
/// | easy       | 420 µs  | 573 µs  | 641 µs  |
/// | medium     | 7.5 ms  | 22.7 ms | 39.4 ms |
/// | hard       | 44.8 ms | 160 ms  | 237 ms  |
///
/// The gate is **Swift within 2× Go on the same machine**. The assertions below
/// are looser than that because CI hardware is slower and this must not flake;
/// they exist to catch a 3–5× regression. Read the printed table to evaluate the
/// real 2× gate.
///
/// Heavy measurement only runs under `SUDOKU_BENCH=1` (`task bench`, which also
/// builds in release), so the everyday suite stays quick and timing assertions
/// on a loaded machine never become a flakiness source.
private let isBenchmarking = ProcessInfo.processInfo.environment["SUDOKU_BENCH"] == "1"

@Suite("Performance")
struct PerformanceTests {

    private struct Measurement {
        let samples: [Duration]

        init(_ samples: [Duration]) {
            self.samples = samples.sorted()
        }

        func percentile(_ fraction: Double) -> Duration {
            guard !samples.isEmpty else { return .zero }
            let index = min(samples.count - 1, Int(Double(samples.count - 1) * fraction))
            return samples[index]
        }

        var p50: Duration { percentile(0.5) }
        var p90: Duration { percentile(0.9) }
        var max: Duration { samples.last ?? .zero }
    }

    private static func measure(_ count: Int, _ body: (UInt64) -> Void) -> Measurement {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        samples.reserveCapacity(count)
        for sample in 0..<count {
            samples.append(clock.measure { body(UInt64(sample)) })
        }
        return Measurement(samples)
    }

    private static func report(_ label: String, _ measurement: Measurement) {
        func ms(_ duration: Duration) -> String {
            let milliseconds =
                Double(duration.components.seconds) * 1000
                + Double(duration.components.attoseconds) / 1e15
            return String(format: "%8.3f ms", milliseconds)
        }
        let name = label.padding(toLength: 8, withPad: " ", startingAt: 0)
        print("  \(name) p50 \(ms(measurement.p50))  p90 \(ms(measurement.p90))  max \(ms(measurement.max))")
    }

    // MARK: - Budgets

    /// Loose ceilings sized for slow CI hardware. The real gate is the printed
    /// table compared against the Go baseline above.
    private static let budgets: [Difficulty: Duration] = [
        .easy: .milliseconds(50),
        .medium: .milliseconds(600),
        .hard: .milliseconds(2500),
        .expert: .milliseconds(4000),
    ]

    @Test(
        "generation stays inside its p90 budget",
        .enabled(if: isBenchmarking, "set SUDOKU_BENCH=1, or run `task bench`"),
        arguments: Difficulty.allCases
    )
    func generationBudget(difficulty: Difficulty) {
        let samples =
            switch difficulty {
            case .easy: 40
            case .medium: 20
            default: 10
            }

        let measurement = Self.measure(samples) { seed in
            var rng = SeededRandom(seed: seed)
            _ = Generator.generate(difficulty, using: &rng)
        }
        Self.report(difficulty.rawValue, measurement)

        guard let budget = Self.budgets[difficulty] else { return }
        #expect(
            measurement.p90 <= budget,
            "\(difficulty) p90 \(measurement.p90) exceeds the \(budget) budget"
        )
    }

    /// `rate` and `countSolutions` are called once per removal attempt, so their
    /// individual cost multiplies by roughly 81 × attempts. Tracking them
    /// separately says *which* half of the carve loop regressed.
    @Test(
        "the carve loop's two hot calls stay cheap",
        .enabled(if: isBenchmarking, "set SUDOKU_BENCH=1, or run `task bench`")
    )
    func hotPathCost() {
        let puzzles = Fixtures.corpus(kind: "generated-hard").prefix(20).map(\.grid)

        let rating = Self.measure(puzzles.count) { index in
            _ = Rater.rate(puzzles[Int(index)])
        }
        let counting = Self.measure(puzzles.count) { index in
            _ = Solver.countSolutions(puzzles[Int(index)], limit: 2)
        }

        print("  hot path (per call, hard puzzles):")
        Self.report("rate", rating)
        Self.report("count", counting)

        #expect(rating.p90 <= .milliseconds(20))
        #expect(counting.p90 <= .milliseconds(20))
    }

    /// Reproducibility must survive optimisation. A release build that reorders
    /// RNG consumption would break every past daily, and would do it silently.
    @Test("generation stays reproducible in release builds")
    func reproducibleUnderOptimisation() {
        for difficulty in Difficulty.allCases {
            var first = SeededRandom(seed: 555)
            var second = SeededRandom(seed: 555)
            #expect(
                Generator.generate(difficulty, using: &first) == Generator.generate(difficulty, using: &second),
                "\(difficulty) is not reproducible"
            )
        }
    }
}
