import Foundation
import Testing

@testable import SudokuKit

@Suite("Puzzle pool")
struct PuzzlePoolTests {

    /// A scratch file that cleans up after itself.
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pool-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pool.json")
    }

    private func pool(
        difficulties: [Difficulty] = [.easy],
        depth: Int = 2,
        storageURL: URL? = nil,
        seed: UInt64 = 1,
        power: @escaping @Sendable () -> PuzzlePool.PowerState = { .normal }
    ) -> PuzzlePool {
        PuzzlePool(
            configuration: .init(difficulties: difficulties, targetDepth: depth, storageURL: storageURL),
            seed: seed,
            powerState: power
        )
    }

    // MARK: - Taking

    @Test("an empty pool still yields a puzzle")
    func takeFromEmptyPool() async {
        let pool = pool()
        let puzzle = await pool.take(.easy)

        #expect(puzzle.difficulty == .easy)
        #expect(Solver.hasUniqueSolution(puzzle.puzzle))
        #expect(Solver.solve(puzzle.puzzle) == puzzle.solution)
    }

    /// The server's pool blocks callers until a filler produces something. A
    /// phone has one user already looking at the screen, so an empty buffer must
    /// mean "generate now", not "wait".
    @Test("taking never waits on a refill")
    func takeDoesNotBlockOnRefill() async {
        let pool = pool()
        // No refill has run, so this can only be served by generating inline.
        let puzzle = await pool.take(.easy)
        #expect(puzzle.puzzle.clueCount > 0)
    }

    @Test("a buffered puzzle is served from the buffer")
    func takeConsumesBuffer() async {
        let pool = pool(depth: 2)
        await pool.refill()
        #expect(await pool.counts()[.easy] == 2)

        let first = await pool.take(.easy)
        #expect(await pool.counts()[.easy] == 1)

        let second = await pool.take(.easy)
        #expect(await pool.counts()[.easy] == 0)
        #expect(first != second, "the buffer should not hand out the same puzzle twice")
    }

    @Test("puzzles are varied, not repeated")
    func puzzlesAreVaried() async {
        let pool = pool(depth: 3)
        var seen = Set<String>()
        for _ in 0..<6 {
            seen.insert(await pool.take(.easy).puzzle.digits())
        }
        #expect(seen.count == 6, "the pool handed out duplicates")
    }

    @Test("every rung can be taken", arguments: Difficulty.allCases)
    func takeEachDifficulty(difficulty: Difficulty) async {
        let pool = pool(difficulties: [difficulty], depth: 1)
        let puzzle = await pool.take(difficulty)

        #expect(puzzle.difficulty == difficulty)
        #expect(puzzle.tier <= difficulty.spec.maxTier)
        #expect(Solver.hasUniqueSolution(puzzle.puzzle))
    }

    // MARK: - Filling

    @Test("refill tops every rung up to the target")
    func refillReachesTarget() async {
        let pool = pool(difficulties: [.easy, .medium], depth: 2)
        await pool.refill()

        #expect(await pool.isFull)
        #expect(await pool.counts() == [.easy: 2, .medium: 2])
    }

    @Test("refill on a full pool does nothing")
    func refillIsIdempotent() async {
        let pool = pool(depth: 1)
        await pool.refill()
        let before = await pool.counts()

        await pool.refill()
        #expect(await pool.counts() == before)
    }

    /// Filling the neediest rung first means a refill cut short — by the app
    /// backgrounding, or the device warming up — still leaves the buffer evenly
    /// spread rather than deep in one rung and empty in another.
    @Test("refill spreads across rungs rather than filling one")
    func refillSpreadsEvenly() async {
        let pool = pool(difficulties: [.easy, .medium], depth: 3)
        await pool.refill()

        let counts = await pool.counts()
        #expect(counts[.easy] == 3)
        #expect(counts[.medium] == 3)
    }

    @Test("a constrained device does not refill")
    func powerConstrainedSkipsRefill() async {
        let pool = pool(depth: 3, power: { .constrained })
        await pool.refill()

        #expect(await pool.counts()[.easy] == 0, "a hot or throttled device should not generate speculatively")
    }

    /// The player asked for this one, so it happens regardless — the power check
    /// only governs speculative work.
    @Test("a constrained device still serves a take")
    func powerConstrainedStillServesTake() async {
        let pool = pool(power: { .constrained })
        let puzzle = await pool.take(.easy)
        #expect(Solver.hasUniqueSolution(puzzle.puzzle))
    }

    @Test("a cancelled refill stops early")
    func refillHonoursCancellation() async {
        let pool = pool(difficulties: Difficulty.allCases, depth: 3)

        let task = Task { await pool.refill() }
        task.cancel()
        await task.value

        #expect(!(await pool.isFull), "a cancelled refill should not have completed")
    }

    // MARK: - Priming

    @Test("priming fills the buffer without generating")
    func priming() async {
        let pool = pool(difficulties: [.easy, .medium], depth: 2)

        var rng = SeededRandom(seed: 42)
        let prepared = [
            Generator.generate(.easy, using: &rng),
            Generator.generate(.easy, using: &rng),
            Generator.generate(.medium, using: &rng),
        ]
        await pool.prime(with: prepared)

        #expect(await pool.counts() == [.easy: 2, .medium: 1])
        #expect(await pool.take(.easy) == prepared[0])
    }

    @Test("priming respects the target depth")
    func primingDoesNotOverfill() async {
        let pool = pool(depth: 1)
        var rng = SeededRandom(seed: 7)
        let prepared = (0..<5).map { _ in Generator.generate(.easy, using: &rng) }

        await pool.prime(with: prepared)
        #expect(await pool.counts()[.easy] == 1)
    }

    @Test("priming ignores rungs the pool does not serve")
    func primingIgnoresUnknownRungs() async {
        let pool = pool(difficulties: [.easy], depth: 3)
        var rng = SeededRandom(seed: 7)
        await pool.prime(with: [Generator.generate(.expert, using: &rng)])

        #expect(await pool.counts() == [.easy: 0])
    }

    // MARK: - Persistence

    @Test("a saved buffer survives a restart")
    func persistenceRoundTrip() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = pool(difficulties: [.easy, .medium], depth: 2, storageURL: url)
        await original.refill()
        let saved = try await original.save()
        #expect(saved)

        let expected = await original.counts()

        // A fresh pool, as if the app had been force-quit and relaunched.
        let restored = pool(difficulties: [.easy, .medium], depth: 2, storageURL: url, seed: 999)
        let count = await restored.restore()

        #expect(count == 4)
        #expect(await restored.counts() == expected)

        let puzzle = await restored.take(.easy)
        #expect(Solver.hasUniqueSolution(puzzle.puzzle), "a restored puzzle must still be playable")
        #expect(Solver.solve(puzzle.puzzle) == puzzle.solution, "the solution must survive the round trip")
    }

    @Test("saving is skipped when nothing changed")
    func saveSkipsCleanBuffer() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let pool = pool(storageURL: url)
        #expect(try await pool.save() == false, "an untouched pool has nothing to write")

        await pool.refill()
        #expect(try await pool.save() == true)
        #expect(try await pool.save() == false, "a second save with no changes is pointless work")
    }

    @Test("an in-memory pool never writes to disk")
    func inMemoryPoolDoesNotPersist() async throws {
        let pool = pool(storageURL: nil)
        await pool.refill()
        #expect(try await pool.save() == false)
        #expect(await pool.restore() == 0)
    }

    /// The pool is a cache. Every way of failing to read it has to degrade to
    /// "start empty" — a cache that can fail a launch is worse than no cache.
    @Test("a missing store restores nothing and does not fail")
    func restoreMissingFile() async {
        let pool = pool(storageURL: temporaryURL())
        #expect(await pool.restore() == 0)
        #expect(await pool.take(.easy).difficulty == .easy, "the pool still works")
    }

    @Test("a corrupt store restores nothing and does not fail")
    func restoreCorruptFile() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("this is not the json you are looking for".utf8).write(to: url)

        let pool = pool(storageURL: url)
        #expect(await pool.restore() == 0)
        #expect(await pool.take(.easy).difficulty == .easy)
    }

    @Test("an entry that no longer parses is dropped, not the whole buffer")
    func restoreSkipsBadEntries() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let source = pool(depth: 2, storageURL: url)
        await source.refill()
        try await source.save()

        // Corrupt exactly one entry's puzzle string.
        var entries = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]] ?? []
        #expect(entries.count == 2)
        entries[0]["puzzle"] = "much too short"
        try JSONSerialization.data(withJSONObject: entries).write(to: url)

        let restored = pool(depth: 2, storageURL: url)
        #expect(await restored.restore() == 1, "the good entry should survive its corrupt neighbour")
    }

    @Test("clearing empties the buffer and removes the file")
    func clear() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let pool = pool(storageURL: url)
        await pool.refill()
        try await pool.save()
        #expect(FileManager.default.fileExists(atPath: url.path))

        await pool.clear()
        #expect(await pool.counts()[.easy] == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Concurrency

    /// The property that justifies the actor: carving is solid CPU work, so
    /// doing it inside the actor would block every other message — including the
    /// `take` a player is waiting on. Generation is handed to a detached task and
    /// only the result comes back.
    @Test("a take is served while a refill is running")
    func takeIsNotBlockedByRefill() async {
        let pool = pool(difficulties: Difficulty.allCases, depth: 3)

        async let refilling: Void = pool.refill()
        async let puzzle = pool.take(.easy)

        let taken = await puzzle
        await refilling

        #expect(Solver.hasUniqueSolution(taken.puzzle))
        #expect(await pool.isFull, "the refill should still have finished")
    }

    @Test("concurrent takes never hand out the same puzzle")
    func concurrentTakesAreDistinct() async {
        let pool = pool(depth: 3)
        await pool.refill()

        let puzzles = await withTaskGroup(of: GeneratedPuzzle.self) { group in
            for _ in 0..<6 { group.addTask { await pool.take(.easy) } }
            var collected: [GeneratedPuzzle] = []
            for await puzzle in group { collected.append(puzzle) }
            return collected
        }

        #expect(Set(puzzles.map { $0.puzzle.digits() }).count == 6, "a puzzle was handed out twice")
    }
}
