import Foundation

/// A warm buffer of ready-to-play puzzles.
///
/// Port of the idea in `backend/internal/generator/pool.go`, with the phone's
/// constraints substituted for the server's. Three differences are deliberate:
///
/// - **The server blocks; this does not.** `pool.go` makes callers wait for a
///   background filler, because bounding CPU across many concurrent requests
///   matters more than any one request's latency. A phone has one user, already
///   looking at the screen. `take` therefore returns a buffered puzzle if there
///   is one and generates inline otherwise — which the measured generation cost
///   makes affordable (Gate G1: expert p50 8 ms).
/// - **The buffer is small.** Three per difficulty, not the server's sixteen.
/// - **It survives a cold launch.** The buffer persists to disk, so the first
///   "New game" after an app restart is instant rather than merely fast.
///
/// Because generation is no longer a latency risk, this is polish rather than
/// load-bearing infrastructure: a pool that is empty, stale, or disabled costs a
/// few milliseconds, not a spinner.
public actor PuzzlePool {

    /// How much to keep, and where.
    public struct Configuration: Sendable {
        /// Which rungs to keep buffered.
        public var difficulties: [Difficulty]
        /// How many ready puzzles to hold per difficulty.
        public var targetDepth: Int
        /// Where to persist the buffer. `nil` keeps the pool in memory only,
        /// which is what tests and previews want.
        public var storageURL: URL?

        public init(
            difficulties: [Difficulty] = Difficulty.allCases,
            targetDepth: Int = 3,
            storageURL: URL? = nil
        ) {
            self.difficulties = difficulties
            self.targetDepth = targetDepth
            self.storageURL = storageURL
        }
    }

    /// Whether the device can afford background generation right now.
    public enum PowerState: Sendable {
        case normal
        /// Low Power Mode, or a device already running hot. Refilling stops;
        /// `take` still works, because the player asked for that one.
        case constrained
    }

    private let configuration: Configuration
    private let powerState: @Sendable () -> PowerState
    private var ready: [Difficulty: [GeneratedPuzzle]] = [:]
    private var rng: SeededRandom
    /// Set when the buffer changes, so `save` can skip pointless writes.
    private var isDirty = false

    /// - Parameters:
    ///   - seed: seeds the pool's own RNG. Puzzles from the pool are meant to be
    ///     varied rather than reproducible, so the app should seed from the
    ///     clock; tests pin it. SudokuKit never touches the global RNG, so the
    ///     seed has to come from somewhere, and an explicit parameter beats a
    ///     hidden dependency.
    ///   - powerState: injectable so tests can simulate a hot or throttled
    ///     device without one.
    public init(
        configuration: Configuration = Configuration(),
        seed: UInt64,
        powerState: @escaping @Sendable () -> PowerState = PuzzlePool.systemPowerState
    ) {
        self.configuration = configuration
        self.rng = SeededRandom(seed: seed)
        self.powerState = powerState
    }

    // MARK: - Taking

    /// A puzzle of the requested difficulty, from the buffer when possible.
    ///
    /// Never fails and never waits on a background filler: an empty buffer means
    /// generating one now.
    public func take(_ difficulty: Difficulty) async -> GeneratedPuzzle {
        if var buffered = ready[difficulty], !buffered.isEmpty {
            let puzzle = buffered.removeFirst()
            ready[difficulty] = buffered
            isDirty = true
            return puzzle
        }
        return await generate(difficulty)
    }

    /// How many puzzles are buffered per difficulty.
    public func counts() -> [Difficulty: Int] {
        configuration.difficulties.reduce(into: [:]) { counts, difficulty in
            counts[difficulty] = ready[difficulty]?.count ?? 0
        }
    }

    /// Whether every rung is at target depth.
    public var isFull: Bool {
        configuration.difficulties.allSatisfy {
            (ready[$0]?.count ?? 0) >= configuration.targetDepth
        }
    }

    // MARK: - Filling

    /// Tops every rung up to `targetDepth`.
    ///
    /// Intended to run from a low-priority background `Task` on launch and when
    /// the app backgrounds. Stops early if the device is thermally or
    /// power-constrained, or if the task is cancelled — a puzzle nobody has
    /// asked for is never worth a hot phone.
    public func refill() async {
        while let difficulty = neediestDifficulty() {
            if Task.isCancelled { return }
            guard powerState() == .normal else { return }

            let puzzle = await generate(difficulty)
            ready[difficulty, default: []].append(puzzle)
            isDirty = true
        }
    }

    /// Fills the buffer from a pre-generated set, for a first launch that has
    /// never run the generator.
    public func prime(with puzzles: [GeneratedPuzzle]) {
        for puzzle in puzzles where configuration.difficulties.contains(puzzle.difficulty) {
            var buffered = ready[puzzle.difficulty] ?? []
            guard buffered.count < configuration.targetDepth else { continue }
            buffered.append(puzzle)
            ready[puzzle.difficulty] = buffered
            isDirty = true
        }
    }

    /// The rung furthest below target, or nil when every rung is full. Filling
    /// the neediest first means a half-finished refill still leaves the buffer
    /// evenly spread rather than deep in one rung and empty in another.
    private func neediestDifficulty() -> Difficulty? {
        configuration.difficulties
            .map { ($0, ready[$0]?.count ?? 0) }
            .filter { $0.1 < configuration.targetDepth }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Generates off the actor.
    ///
    /// Carving is hundreds of milliseconds of solid CPU work. Running it inside
    /// the actor would block every other message — including the `take` that a
    /// player is waiting on — so the work is handed to a detached task and only
    /// the result comes back.
    private func generate(_ difficulty: Difficulty) async -> GeneratedPuzzle {
        let seed = rng.next()
        return await Task.detached(priority: .utility) {
            var rng = SeededRandom(seed: seed)
            return Generator.generate(difficulty, using: &rng)
        }.value
    }

    // MARK: - Persistence

    /// A stored puzzle. Grids travel as their 81-character form: compact,
    /// diffable, and the same representation the fixtures and share codes use.
    private struct StoredPuzzle: Codable {
        let difficulty: Difficulty
        let puzzle: String
        let solution: String
        let tier: Int

        init(_ generated: GeneratedPuzzle) {
            difficulty = generated.difficulty
            puzzle = generated.puzzle.digits()
            solution = generated.solution.digits()
            tier = generated.tier.rawValue
        }

        /// Returns nil rather than throwing: a corrupt entry should cost one
        /// puzzle, not the whole buffer.
        var generated: GeneratedPuzzle? {
            guard let puzzle = Grid(digits: puzzle),
                let solution = Grid(digits: solution),
                let tier = Tier(rawValue: tier)
            else { return nil }
            return GeneratedPuzzle(puzzle: puzzle, solution: solution, difficulty: difficulty, tier: tier)
        }
    }

    /// Writes the buffer to disk, so a cold launch starts warm.
    @discardableResult
    public func save() throws -> Bool {
        guard let url = configuration.storageURL, isDirty else { return false }

        let stored = configuration.difficulties
            .flatMap { ready[$0] ?? [] }
            .map(StoredPuzzle.init)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(stored).write(to: url, options: .atomic)
        isDirty = false
        return true
    }

    /// Restores a persisted buffer.
    ///
    /// Every failure — missing file, unreadable data, a puzzle that no longer
    /// parses — is treated the same way: start empty. The pool is a cache, and a
    /// cache that can fail a launch is worse than no cache.
    @discardableResult
    public func restore() -> Int {
        guard let url = configuration.storageURL,
            let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode([StoredPuzzle].self, from: data)
        else { return 0 }

        ready = [:]
        var restored = 0
        for entry in stored {
            guard let generated = entry.generated,
                configuration.difficulties.contains(generated.difficulty),
                (ready[generated.difficulty]?.count ?? 0) < configuration.targetDepth
            else { continue }
            ready[generated.difficulty, default: []].append(generated)
            restored += 1
        }
        isDirty = false
        return restored
    }

    /// Empties the buffer and removes any persisted copy.
    public func clear() {
        ready = [:]
        isDirty = false
        if let url = configuration.storageURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Power

    /// Reads the device's thermal and power state.
    ///
    /// Background generation is a nice-to-have; a warm phone or a nearly flat
    /// battery is not worth a puzzle nobody has asked for yet.
    public static let systemPowerState: @Sendable () -> PowerState = {
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return .constrained }
        switch info.thermalState {
        case .serious, .critical: return .constrained
        default: return .normal
        }
    }
}
