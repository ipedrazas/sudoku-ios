import Foundation
import SudokuKit

/// Supplies puzzles to the UI, and keeps the pool warm behind it.
///
/// The pool is an actor and generation is asynchronous, so the views need
/// something main-actor-bound to observe. This is that seam — and the only place
/// in the app that knows a pool exists.
@Observable
@MainActor
final class PuzzleProvider {
    private let pool: PuzzlePool
    private var refillTask: Task<Void, Never>?

    private(set) var isGenerating = false

    init() {
        // SudokuKit never touches the global RNG, so a seed has to come from
        // outside it. Pool puzzles are meant to be varied rather than
        // reproducible — unlike the daily, which is seeded from its date.
        let seed = UInt64(Date().timeIntervalSince1970 * 1000)
        pool = PuzzlePool(
            configuration: .init(storageURL: Self.storageURL),
            seed: seed
        )
    }

    /// Restores the persisted buffer and tops it up in the background.
    ///
    /// Restoring is cheap and synchronous-ish; refilling is not, so it runs at
    /// low priority and is cancelled if the app moves on.
    func warmUp() {
        refillTask?.cancel()
        refillTask = Task(priority: .utility) {
            _ = await pool.restore()
            await pool.refill()
            _ = try? await pool.save()
        }
    }

    /// Stops background work and persists whatever is buffered. Called when the
    /// app leaves the foreground.
    func suspend() async {
        refillTask?.cancel()
        refillTask = nil
        _ = try? await pool.save()
    }

    /// A puzzle of the requested difficulty.
    ///
    /// `isGenerating` exists for the case where the buffer is empty and this has
    /// to generate inline. Measured, that is single-digit milliseconds, so the
    /// UI should not show a spinner for it — but it should not lie about being
    /// idle either.
    func newGame(_ difficulty: Difficulty) async -> GeneratedPuzzle {
        isGenerating = true
        defer { isGenerating = false }

        let puzzle = await pool.take(difficulty)
        warmUp()
        return puzzle
    }

    /// `Application Support/pool.json`, created on demand.
    private static var storageURL: URL? {
        guard
            let directory = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        else { return nil }
        return directory.appendingPathComponent("pool.json")
    }
}
