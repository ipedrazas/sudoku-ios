# Persisted schema, v1 — frozen

Frozen at P4-7 (Phase 4 of [`implementation-plan.md`](./implementation-plan.md)).
Defined in `SudokuApp/Sources/Persistence/PersistenceModels.swift` and enumerated
by `SchemaV1.models`.

**Frozen means additive.** Later phases add entities and add optional fields to
existing ones. They do not rename, retype or remove anything, and they do not
change an encoding. The reason is §11 of the plan: schema churn after launch is
migration pain, and the migration is the expensive part, not the schema.

---

## The three CloudKit rules

Sync is off. Every model still obeys the rules CloudKit imposes, so turning it on
later is `ModelConfiguration(cloudKitDatabase: .private)` and nothing else:

| Rule | Why | What it costs here |
|---|---|---|
| No `@Attribute(.unique)` | CloudKit has no uniqueness constraint | `PuzzleRecord.id` uniqueness is maintained by `SwiftDataRepository`, not the store |
| Every property optional | CloudKit records arrive field by field; a non-optional with no default is unrepresentable | Every read goes through a `snapshot` accessor that validates and returns nil |
| No relationships | Avoids the "every relationship needs an inverse" rule entirely | Rows reference each other by `UUID`; deletes are explicit |

The consequence worth stating plainly: **the database enforces nothing.** The
repository is the only thing keeping the store consistent, which is why both
implementations are held to one contract by `PersistenceTests`.

---

## Entities

### `PuzzleRecord` — a puzzle as dealt

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID?` | Shared with `GameSession.id`. Unique by convention. |
| `puzzle` | `Data?` | 81 bytes, row-major, `0` = empty |
| `solution` | `Data?` | 81 bytes, always full |
| `difficultyRaw` | `String?` | `Difficulty.rawValue`: `easy` · `medium` · `hard` · `expert` |
| `tier` | `Int?` | `Tier.rawValue`, 1…5 — the tier the puzzle *actually* rates |
| `sourceRaw` | `String?` | `generated` · `daily` · `imported` · `shared` |
| `dateKey` | `String?` | `"YYYY-MM-DD"` UTC for dailies, nil otherwise |
| `createdAt` | `Date?` | |

Lifetime: outlives its `SavedGame`. Deleted when its saved game is deleted
**unless** a `Completion` refers to it or it has a `dateKey` — the history and
the calendar both have to keep pointing at something real.

### `SavedGame` — a game in progress

| Field | Type | Notes |
|---|---|---|
| `puzzleID` | `UUID?` | → `PuzzleRecord.id`. One saved game per puzzle. |
| `board` | `Data?` | 81 bytes, givens included |
| `pencil` | `Data?` | 162 bytes: 81 little-endian `UInt16` masks |
| `elapsedSeconds` | `Int?` | |
| `hintsUsed` | `Int?` | Reveals only — the web schema's `hints_used` |
| `hintPoints` | `Int?` | Weighted cost across all hint levels |
| `updatedAt` | `Date?` | Sorts the resume list |

Deleted when the puzzle is solved. A row whose `PuzzleRecord` is missing or
unreadable is not offered for resuming.

### `Completion` — a finished puzzle

| Field | Type | Notes |
|---|---|---|
| `puzzleID` | `UUID?` | Nil is tolerated; stats never need the puzzle back |
| `difficultyRaw` | `String?` | |
| `timeSeconds` | `Int?` | |
| `hintsUsed` | `Int?` | |
| `completedAt` | `Date?` | Streaks count **UTC** days from this |

The source of truth for stats, streaks and achievements. All three are
recomputed from these rows rather than tracked incrementally, so a deleted game
or a restored backup can never leave a running total lying.

### `AchievementRecord` — one unlock

| Field | Type | Notes |
|---|---|---|
| `key` | `String?` | One of the 11 frozen keys in `Achievements.all` |
| `unlockedAt` | `Date?` | |

Unlocking is idempotent. An unrecognised key is ignored rather than shown, so a
row written by a newer build cannot break an older one.

---

## Encodings

Grids and pencil marks are raw bytes, not JSON and not strings: fixed length, no
parser, nothing to version.

```
Grid    81 bytes    cell[i] = digit 0…9, row-major
Pencil  162 bytes   mask[i] = UInt16 little-endian; bit d set ⇒ digit d pencilled
```

Both decoders validate length and range and return nil on anything else. A
corrupt row costs a saved game; it never produces a subtly wrong board. Pencil
marks are the one field that degrades rather than fails — an unreadable pencil
blob loads as empty marks, because losing candidates is annoying and losing the
board is the game.

`UInt16` masks rather than `[[Int]]` are the same representation the solver uses,
so nothing converts at the hint boundary.

---

## What is deliberately *not* here

- **Settings** live in `@AppStorage`, not SwiftData. They are per-device
  preferences, they are tiny, and they have no history.
- **The puzzle pool** persists itself to `Application Support/pool.json`
  (`PuzzlePool`). It is a cache: every read failure degrades to "start empty",
  which is exactly what a database would make harder.
- **Hint history** is not stored. `hintPoints` and `hintsUsed` are the totals
  that matter; which hints were taken in what order is not.

## Reserved for later phases

Additive, and already accounted for in the shape above:

| Phase | Addition |
|---|---|
| 5 — Daily | None. Dailies are `PuzzleRecord`s with a `dateKey`, and the lookup already exists. |
| 6 — Stats | None. Everything is derived from `Completion`. |
| 7 — Import/share | None. Imported and shared puzzles are `PuzzleRecord`s with a `sourceRaw`. |
| 8 — Widgets | Nothing in SwiftData. The widget reads an App Group JSON snapshot and never opens this store. |
