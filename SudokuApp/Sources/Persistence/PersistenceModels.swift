import Foundation
import SwiftData

/// Where a puzzle came from.
///
/// Stored as a string rather than an integer so an unrecognised value from a
/// future version is still readable, and so the store is legible when inspected
/// by hand.
enum PuzzleSource: String, Codable, Sendable, CaseIterable {
    case generated
    case daily
    case imported
    case shared
}

/// The persisted schema. **Frozen at P4-7 — see `plans/schema-v1.md`.**
///
/// Every model here obeys three CloudKit rules even though sync is off:
///
/// 1. No `@Attribute(.unique)`. CloudKit has no uniqueness constraint, so a
///    model that relies on one cannot be synced without a migration.
/// 2. Every property is optional. CloudKit records arrive field by field and a
///    non-optional property with no default is unrepresentable.
/// 3. No relationships. Rows reference each other by `UUID`, which sidesteps the
///    inverse-relationship requirement entirely and keeps deletes explicit.
///
/// The cost is that nothing in the store is enforced by the database: uniqueness
/// of `PuzzleRecord.id` and the `SavedGame` → `PuzzleRecord` reference are both
/// invariants the repository maintains. That is the trade the plan makes
/// deliberately (§6.2) — enabling sync later should be one line, not a migration.
enum SchemaV1 {
    static let models: [any PersistentModel.Type] = [
        PuzzleRecord.self,
        SavedGame.self,
        Completion.self,
        AchievementRecord.self,
    ]
}

/// A puzzle as dealt, with the solution it was carved from.
///
/// Kept separately from the game in progress because the two have different
/// lifetimes: a puzzle outlives its saved game (a completion still refers to it)
/// and the same puzzle can be replayed.
@Model
final class PuzzleRecord {
    var id: UUID?
    /// 81 bytes, one per cell, row-major. 0 is empty.
    var puzzle: Data?
    /// 81 bytes. Always full — the solution is known at generation time, and at
    /// import time it is computed before the puzzle is accepted.
    var solution: Data?
    var difficultyRaw: String?
    /// The tier the puzzle actually rates, which is not always the rung's target.
    var tier: Int?
    var sourceRaw: String?
    /// `"YYYY-MM-DD"` (UTC) for dailies, nil otherwise. Phase 5 looks a daily up
    /// by this rather than regenerating it.
    var dateKey: String?
    var createdAt: Date?

    init(
        id: UUID? = nil,
        puzzle: Data? = nil,
        solution: Data? = nil,
        difficultyRaw: String? = nil,
        tier: Int? = nil,
        sourceRaw: String? = nil,
        dateKey: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.puzzle = puzzle
        self.solution = solution
        self.difficultyRaw = difficultyRaw
        self.tier = tier
        self.sourceRaw = sourceRaw
        self.dateKey = dateKey
        self.createdAt = createdAt
    }
}

/// A game in progress. Deleted when the puzzle is solved.
@Model
final class SavedGame {
    var puzzleID: UUID?
    /// 81 bytes: the board as the player has it, givens included.
    var board: Data?
    /// 162 bytes: 81 little-endian `UInt16` candidate masks, the same
    /// representation the solver uses, so nothing converts at the hint boundary.
    var pencil: Data?
    var elapsedSeconds: Int?
    /// Reveals only, kept for continuity with the web schema.
    var hintsUsed: Int?
    /// The weighted cost of every hint level taken.
    var hintPoints: Int?
    var updatedAt: Date?

    init(
        puzzleID: UUID? = nil,
        board: Data? = nil,
        pencil: Data? = nil,
        elapsedSeconds: Int? = nil,
        hintsUsed: Int? = nil,
        hintPoints: Int? = nil,
        updatedAt: Date? = nil
    ) {
        self.puzzleID = puzzleID
        self.board = board
        self.pencil = pencil
        self.elapsedSeconds = elapsedSeconds
        self.hintsUsed = hintsUsed
        self.hintPoints = hintPoints
        self.updatedAt = updatedAt
    }
}

/// A finished puzzle. The row stats and streaks are computed from.
@Model
final class Completion {
    var puzzleID: UUID?
    var difficultyRaw: String?
    var timeSeconds: Int?
    var hintsUsed: Int?
    var completedAt: Date?

    init(
        puzzleID: UUID? = nil,
        difficultyRaw: String? = nil,
        timeSeconds: Int? = nil,
        hintsUsed: Int? = nil,
        completedAt: Date? = nil
    ) {
        self.puzzleID = puzzleID
        self.difficultyRaw = difficultyRaw
        self.timeSeconds = timeSeconds
        self.hintsUsed = hintsUsed
        self.completedAt = completedAt
    }
}

/// One unlocked achievement. The key is one of the 11 frozen keys in
/// `Achievements.all`; unknown keys are ignored rather than shown, so a row
/// written by a future version cannot break this one.
@Model
final class AchievementRecord {
    var key: String?
    var unlockedAt: Date?

    init(key: String? = nil, unlockedAt: Date? = nil) {
        self.key = key
        self.unlockedAt = unlockedAt
    }
}
