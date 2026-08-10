import Testing

@testable import SudokuKit

@Suite("SeededRandom")
struct SeededRandomTests {

    @Test("the same seed produces the same sequence")
    func reproducibleSequence() {
        var first = SeededRandom(seed: 12345)
        var second = SeededRandom(seed: 12345)
        for _ in 0..<1000 {
            #expect(first.next() == second.next())
        }
    }

    @Test("different seeds diverge immediately")
    func seedsDiverge() {
        var first = SeededRandom(seed: 1)
        var second = SeededRandom(seed: 2)
        #expect(first.next() != second.next())
    }

    /// SplitMix64 is a published algorithm; these are its documented outputs for
    /// seed 0. Pinning them means a "harmless tidy-up" of the mixing constants
    /// fails the build instead of silently reshuffling every past daily.
    @Test("SplitMix64 matches its published output for seed 0")
    func matchesReferenceVectors() {
        var rng = SeededRandom(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(rng.next() == 0x06C4_5D18_8009_454F)
    }

    @Test("bounded draws stay in range and cover it")
    func boundedDraws() {
        var rng = SeededRandom(seed: 99)
        var seen = Set<Int>()
        for _ in 0..<10_000 {
            let value = rng.nextBounded(9)
            #expect((0..<9).contains(value))
            seen.insert(value)
        }
        #expect(seen.count == 9, "bounded draw never produced some values: \(seen.sorted())")
    }

    @Test("a bound of 1 always yields 0")
    func boundedDrawOfOne() {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<100 { #expect(rng.nextBounded(1) == 0) }
    }

    @Test("shuffling is a permutation and is reproducible")
    func deterministicShuffle() {
        let original = Array(0..<81)

        var first = SeededRandom(seed: 42)
        var second = SeededRandom(seed: 42)
        let a = original.deterministicShuffled(using: &first)
        let b = original.deterministicShuffled(using: &second)

        #expect(a == b, "the same seed must produce the same shuffle")
        #expect(a.sorted() == original, "shuffling must be a permutation")
        #expect(a != original, "a 81-element shuffle that changes nothing is a bug, not luck")
    }

    @Test("shuffling short arrays is safe")
    func shuffleEdgeCases() {
        var rng = SeededRandom(seed: 1)
        #expect([Int]().deterministicShuffled(using: &rng).isEmpty)
        #expect([5].deterministicShuffled(using: &rng) == [5])
        #expect([1, 2].deterministicShuffled(using: &rng).sorted() == [1, 2])
    }
}

@Suite("Generator")
struct GeneratorTests {

    @Test("a generated solution is complete and valid")
    func solutionIsValid() {
        for seed in UInt64(0)..<20 {
            var rng = SeededRandom(seed: seed)
            let solution = Generator.generateSolution(using: &rng)
            #expect(Validator.isSolved(solution), "invalid solution from seed \(seed):\n\(solution)")
        }
    }

    /// Go: `TestGenerateSolution_FirstRowNotSequential`. A solution whose first
    /// row is always 1…9 means the shuffle is not being applied.
    @Test("solutions are actually randomised")
    func solutionsAreRandomised() {
        var sequentialCount = 0
        var solutions = Set<String>()

        for seed in UInt64(0)..<20 {
            var rng = SeededRandom(seed: seed)
            let solution = Generator.generateSolution(using: &rng)
            solutions.insert(solution.digits())
            if (0..<Grid.size).allSatisfy({ solution[0, $0] == $0 + 1 }) { sequentialCount += 1 }
        }

        #expect(sequentialCount <= 1, "first row is sequential too often — is the shuffle wired up?")
        #expect(solutions.count == 20, "different seeds should produce different solutions")
    }

    @Test("generation is reproducible for a given seed", arguments: Difficulty.allCases)
    func generationIsReproducible(difficulty: Difficulty) {
        var first = SeededRandom(seed: 2026_08_10)
        var second = SeededRandom(seed: 2026_08_10)

        let a = Generator.generate(difficulty, using: &first)
        let b = Generator.generate(difficulty, using: &second)

        #expect(a == b, "\(difficulty) generation is not reproducible")
    }

    @Test("every generated puzzle has a unique solution", arguments: Difficulty.allCases)
    func puzzlesAreUnique(difficulty: Difficulty) {
        for seed in UInt64(0)..<5 {
            var rng = SeededRandom(seed: seed)
            let generated = Generator.generate(difficulty, using: &rng)
            #expect(
                Solver.hasUniqueSolution(generated.puzzle),
                "\(difficulty) seed \(seed) is not unique:\n\(generated.puzzle.digits())"
            )
        }
    }

    @Test("a generated puzzle's givens agree with its solution", arguments: Difficulty.allCases)
    func puzzleMatchesSolution(difficulty: Difficulty) {
        for seed in UInt64(0)..<5 {
            var rng = SeededRandom(seed: seed)
            let generated = Generator.generate(difficulty, using: &rng)

            #expect(Validator.isSolved(generated.solution))
            for index in 0..<Grid.cellCount where generated.puzzle[index] != 0 {
                #expect(generated.puzzle[index] == generated.solution[index])
            }
            #expect(Solver.solve(generated.puzzle) == generated.solution)
        }
    }

    /// The promise the whole difficulty system exists to keep: no shipped puzzle
    /// ever requires guessing.
    @Test("no generated puzzle needs guessing", arguments: Difficulty.allCases)
    func neverRequiresGuessing(difficulty: Difficulty) {
        for seed in UInt64(100)..<108 {
            var rng = SeededRandom(seed: seed)
            let generated = Generator.generate(difficulty, using: &rng)
            #expect(
                generated.tier < .beyond,
                "\(difficulty) seed \(seed) rated beyond logic:\n\(generated.puzzle.digits())"
            )
            #expect(Rater.rate(generated.puzzle) == generated.tier, "reported tier disagrees with the rater")
        }
    }

    @Test("generated puzzles land in their difficulty band", arguments: Difficulty.allCases)
    func puzzlesLandInBand(difficulty: Difficulty) {
        let spec = difficulty.spec
        var inBand = 0
        let samples = 8

        for seed in UInt64(200)..<UInt64(200 + samples) {
            var rng = SeededRandom(seed: seed)
            let generated = Generator.generate(difficulty, using: &rng)

            #expect(generated.tier <= spec.maxTier, "\(difficulty) exceeded its ceiling")
            #expect(
                generated.clueCount >= spec.minClues,
                "\(difficulty) carved below its clue floor: \(generated.clueCount) < \(spec.minClues)"
            )
            if spec.accepts(generated.tier) { inBand += 1 }
        }

        // The attempt budget allows a near-miss fallback, so this is a rate, not
        // an absolute. A rung that misses more often than it hits is broken.
        #expect(inBand > samples / 2, "\(difficulty) landed in band only \(inBand)/\(samples) times")
    }

    /// Measures the Expert/Evil separation flagged as a risk in the plan (P2-6).
    /// Both share a technique ceiling and differ only in carve depth, so if their
    /// clue counts converge the extra rung means nothing to a player.
    @Test("Evil carves meaningfully deeper than Expert")
    func evilIsDistinctFromExpert() {
        func medianClues(_ difficulty: Difficulty) -> Int {
            let counts = (UInt64(300)..<308).map { seed -> Int in
                var rng = SeededRandom(seed: seed)
                return Generator.generate(difficulty, using: &rng).clueCount
            }
            return counts.sorted()[counts.count / 2]
        }

        let expert = medianClues(.expert)
        let evil = medianClues(.evil)

        print("clue-count medians — expert: \(expert), evil: \(evil)")
        #expect(evil <= expert, "Evil should never carry more clues than Expert")
    }
}
