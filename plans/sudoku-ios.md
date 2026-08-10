# Sudoku and Cake — iOS App Implementation Plan

**Target:** a standalone, fully offline iPhone/iPad Sudoku app in a new repo, using
`sudoku-and-cake` (web) as the design and feature reference.

**Decisions taken up front:**

| Decision | Choice |
|---|---|
| Sync / accounts | **Fully local, no sync.** No server, no login. Storage layer kept CloudKit-compatible so sync is a later flag-flip, not a rewrite. |
| Platform scope | **Core app + WidgetKit widgets + rich haptics.** No Game Center, no Watch app, no Live Activities in v1. |
| Daily puzzle | **Deterministic on-device generation from the date seed.** Same date → same puzzle on every device, no network. |

---

## 1. What the web app actually does (inventory)

I read the Go backend and React frontend end-to-end. This is the feature and
logic surface worth carrying across.

### 1.1 The crown jewel: technique-based difficulty

`backend/internal/generator/difficulty.go` (509 lines) is the most valuable
thing in the repo and the part most Sudoku apps get wrong. Instead of rating a
puzzle by clue count, it runs a **human-technique solver** and reports the
hardest technique required:

| Tier | Requires |
|---|---|
| `TierNakedSingle` (1) | only "one digit fits here" |
| `TierHiddenSingle` (2) | + "only one cell in this unit takes n" |
| `TierLocked` (3) | + locked candidates (pointing/claiming) or naked pairs |
| `TierAdvanced` (4) | + hidden pairs, naked triples, X-wing |
| `TierBeyond` (5) | needs chains or guessing — rejected |

Candidate sets are `UInt16` bitmasks (`allCandidates = 0x03FE`, bits 1–9), with
the 27 units precomputed once. `Rate()` loops applying techniques cheapest-first
and returns the max tier reached.

Generation (`generator.go`) then **carves to a tier**: fill a full grid by
randomised backtracking, then remove clues one at a time, reverting any removal
that breaks uniqueness (`countSolutions(g, 2) != 1`) or pushes `Rate()` past the
difficulty's ceiling. Carving as deep as the ceiling permits is what makes the
result land *on* the target difficulty.

```
easy:   tier 1–2, min 34 clues, 10 attempts
medium: tier 3–3, min 26 clues, 60 attempts
hard:   tier 4–4, min 22 clues, 80 attempts
```

Every generated puzzle therefore has a **unique solution and is solvable by pure
logic** — "hard" never means "guess". This is the differentiator. Port it
faithfully; do not substitute a clue-count generator.

Consequence: generation is expensive. The Go comment records ~70 ms for one hard
puzzle attempt, and a maximal carve only lands on tier 4 about 10% of the time —
so the worst case for "hard" is 80 × 70 ms ≈ 5.6 s. The web app solves this with
`generator/pool.go`: a background goroutine per difficulty keeping 16 ready
puzzles in a buffered channel, with the blocking send as backpressure. **The iOS
app needs the same thing** (§3.4).

### 1.2 Game features (frontend)

From `useGameBoard.ts` (518 lines), `GamePage.tsx` (983 lines), `Board.tsx`:

- 9×9 board, givens vs entries, per-cell pencil-mark sets (1–9)
- Undo/redo — snapshot stack, cap 100
- Restart to the initial puzzle
- **Error highlighting** (opt-in): highlights every cell in a row/col/box duplicate pair
- **Unit celebration**: a row/col/box that becomes correctly complete animates for 2 s; incorrectly complete units get a distinct warning style
- **Complete-digit dimming**: numpad keys grey out once all nine of a digit are placed
- **Highlight digit**: pick a digit and every matching cell + pencil mark lights up
- **Blind mode**: long-press a filled cell to mask its row and column — a self-imposed difficulty aid
- Win detection computed **locally** (`isSolved`) so a solve registers offline, plus confetti
- Timer with manual pause, and an **inactivity prompt** (1/3/5/10 min, configurable) offering to pause so idle time doesn't inflate the solve time
- Hints: server returns `solution[row][col]` for one cell; `hints_used` is tracked and persisted
- Keyboard shortcuts with fully rebindable keys (`p` pencil, `space` blind, `h` hint, `n` highlight, `⌘Z`/`⌘⇧Z`, `?` help)
- Light/dark theme, system-preference aware
- Manual puzzle import: type in an 81-cell grid from a newspaper (min 17 givens)

### 1.3 Server-side features worth reproducing locally

- **Daily puzzle**: `slug.GenerateForDate(t)` seeds `math/rand` with the UTC-midnight Unix timestamp to derive a deterministic three-word BIP-39 slug per date; the puzzle itself is generated once and stored. Difficulty is a fixed `dailyDifficulty`.
- **Calendar**: per-month grid of daily puzzles up to today, marked played/completed.
- **Saved games**: one checkpoint per user per game — board, pencil, elapsed seconds, hints used.
- **Completions**: one per user per game — difficulty, time, timestamp.
- **Stats** (`/api/stats`): total finished, by difficulty, by day-of-week, by month, recent completions, per-difficulty avg/best time, completion rate, time-distribution buckets, current + best streak.
- **11 achievements** (`achievements.go`, a pure function — trivially portable): first solve per difficulty ×3, speed (easy <5 min, medium <10 min, hard <20 min), milestones (10/50/100 games), streaks (7/30 days).
- BIP-39 three-word slugs as shareable game IDs.

### 1.4 What deliberately does *not* carry over

- **Auth / Supabase / JWT / rate limiting / Postgres / migrations** — all obviated by local-only storage.
- **Photo/OCR import** — per project memory this was attempted twice and removed in Aug 2026; manual entry replaced it. Do not reintroduce it in v1 despite the camera being right there.
- **Shareable slug URLs** — no server to resolve them. Replaced by a self-contained share code (§4.7).
- **Keyboard shortcuts** — replaced by a touch-first input model (§3.6). Keep the hardware-keyboard bindings only if an iPad build ever happens.

---

## 2. Prerequisite: toolchain

`swift --version` reports Swift 6.3.3, but `xcodebuild` is **not** available —
only Command Line Tools are installed. Full Xcode is required for the iOS SDK,
simulators, WidgetKit, and archiving.

This constraint shapes the architecture in a useful way: **all game logic lives
in a platform-agnostic Swift package** that builds and tests with plain
`swift test` on the command line. Only the app shell needs Xcode. Phases 1 and 2
below can begin today; Phase 3 onward needs Xcode installed.

---

## 3. Architecture

### 3.1 Repo layout

```
sudoku-ios/
├── Taskfile.yml                    # same runner as the web repo
├── Package.swift                   # workspace-level SPM manifest
├── SudokuKit/                      # pure Swift, no UIKit, no Foundation-heavy deps
│   ├── Sources/SudokuKit/
│   │   ├── Grid.swift
│   │   ├── Validator.swift
│   │   ├── Solver.swift            # backtracking + solution counting
│   │   ├── Techniques.swift        # port of difficulty.go
│   │   ├── Rater.swift             # Tier + Rate()
│   │   ├── Generator.swift         # carve-to-tier
│   │   ├── SeededRandom.swift      # deterministic RNG for dailies
│   │   ├── HintEngine.swift        # NEW — technique-explaining hints
│   │   ├── ShareCode.swift         # 81-char puzzle encoding
│   │   └── Achievements.swift      # port of achievements.go
│   └── Tests/SudokuKitTests/       # Swift Testing; Go test tables ported
├── SudokuApp/                      # Xcode project (generated by XcodeGen)
│   ├── project.yml
│   ├── Sources/
│   │   ├── App/                    # entry point, routing, theme
│   │   ├── Game/                   # GameSession, BoardView, NumberPad, controls
│   │   ├── Daily/                  # daily + calendar
│   │   ├── Stats/                  # stats + achievements
│   │   ├── Settings/
│   │   ├── Persistence/            # SwiftData models + repositories
│   │   └── Services/               # PuzzlePool, Haptics, Notifications
│   └── Tests/
├── SudokuWidgets/                  # WidgetKit extension
└── .github/workflows/ci.yml
```

**Use XcodeGen** (`project.yml` checked in, `.xcodeproj` gitignored). A hand-
maintained `.pbxproj` is a merge-conflict generator and makes CI reproducibility
worse. `task xcodegen` regenerates.

### 3.2 SudokuKit: the port

Keep it dependency-free and `Sendable` throughout so it can be called from any
actor.

**Grid representation.** Go uses `[9][9]int`. In Swift use a value type over a
flat 81-element storage — better cache behaviour and cheap copies for the undo
stack:

```swift
public struct Grid: Equatable, Sendable {
    private var cells: (UInt8, UInt8, /* ...81 total... */)  // or [UInt8] with COW
    public subscript(row: Int, col: Int) -> Int { get set }
}
```

Simplest correct start: `struct Grid { private var cells: [UInt8] }` (81
elements, copy-on-write). Only reach for a fixed-size tuple or `InlineArray` if
profiling shows allocation pressure in the carve loop — it likely will, since
carving copies the grid thousands of times, so budget a pass for this.

**Candidate masks.** Port `[9][9]uint16` verbatim as `[UInt16]` (81). Swift's
`UInt16.trailingZeroBitCount` and `.nonzeroBitCount` map directly onto
`bits.TrailingZeros16` / `bits.OnesCount16`.

**Units.** `buildUnits()` → a `static let allUnits: [[CellRef]]` computed once.

**Techniques.** `nakedSingles`, `hiddenSingles`, `lockedCandidates` (pointing +
claiming), `nakedSubsets(k)`, `hiddenSubsets(k)`, `xWing` — direct line-by-line
ports. `forEachCombination` becomes a small recursive generator; keep it
allocation-free (reuse a single `pick` buffer as Go does).

**One behavioural change to make deliberately:** `nakedSubsets` in the Go version
builds a `map[[2]int]bool` per combination. In Swift that map allocation inside
the hot loop is far more costly than in Go. Replace it with a `UInt16` bitmask of
unit indices. Same semantics, no allocation.

### 3.3 Deterministic generation

Go's `math/rand` and Swift's RNG produce different sequences, so byte-identical
dailies with the web app are not achievable — and with sync off, not needed.
What *is* needed is that all iOS devices agree.

Implement `SeededRandom: RandomNumberGenerator` using SplitMix64 (tiny, fast,
well-distributed, trivially reproducible). Then:

```swift
public static func daily(for date: Date) -> Puzzle {
    var rng = SeededRandom(seed: UInt64(date.utcMidnightTimestamp))
    return generate(difficulty: .medium, using: &rng)
}
```

Every random draw in `generateSolution` and `carveToTier` must thread through the
injected RNG — no calls to the global RNG anywhere in `SudokuKit`. Enforce this
with a test that generates the same date twice and asserts equality, plus a
golden-value test pinning a handful of known dates so an accidental algorithm
change is caught as a regression rather than silently reshuffling everyone's
daily history.

### 3.4 The puzzle pool

This is the single biggest performance risk. `carveToTier` calls `Rate()` and
`countSolutions()` once per removal attempt — up to 81 removals per attempt,
across up to 80 attempts for hard. Doing that on the main thread will hang the UI
for seconds.

Port `pool.go` as a Swift `actor`:

```swift
actor PuzzlePool {
    private var ready: [Difficulty: [Puzzle]] = [:]
    private let targetDepth = 4          // lower than the server's 16 — a phone has one user
    func take(_ d: Difficulty) async -> Puzzle
    func refill() async                   // Task.detached, low priority
}
```

Three additions the server doesn't need:

1. **Persist the buffer to disk** so a cold launch has puzzles instantly instead of a spinner. Refill in the background on launch and on `scenePhase == .background`.
2. **Seed the first launch from a bundled asset** — ship ~20 pre-generated puzzles per difficulty as a compact JSON/binary resource so the very first "New game" tap is instant, before the generator has ever run.
3. **Respect thermal and battery state** — pause background refills under `ProcessInfo.thermalState >= .serious` or Low Power Mode.

Benchmark `Generator.generate(.hard)` on the oldest supported device early
(Phase 2, not Phase 8). If the worst case is unacceptable, the mitigations in
order of preference are: reduce the `attempts` budget and accept the closest
match (the Go code already has this fallback path), or expand the bundled
pre-generated set.

### 3.5 Persistence

**SwiftData**, with every model designed to be CloudKit-compatible from day one
even though sync is off: no `@Attribute(.unique)`, every property either optional
or with a default, all relationships optional and inverse-declared. Flipping on
`ModelConfiguration(cloudKitDatabase: .private)` later then costs one line
instead of a migration.

```
Puzzle        id, puzzle[81], solution[81], difficulty, tier, source, dateSeed?, createdAt
SavedGame     puzzleID, board[81], pencil[81 × UInt16], elapsedSeconds, hintsUsed, updatedAt
Completion    puzzleID, difficulty, timeSeconds, hintsUsed, completedAt
Achievement   key, unlockedAt
```

Store pencil marks as `[UInt16]` bitmasks, not `[[Int]]` — smaller, and it
matches the solver's representation exactly.

Wrap SwiftData behind `protocol GameRepository` so views never touch a
`ModelContext` directly, tests can use an in-memory implementation, and a sync
provider can be layered in later.

Settings go in `@AppStorage`, mirroring `lib/settings.ts`: inactivity minutes,
error highlighting, theme, haptics, sound, input mode, auto-pencil.

### 3.6 Input model — the biggest UX rethink

The web app is keyboard-first with a mouse fallback. Neither exists on an iPhone.

- **Board sizing.** The web uses `min(82vmin, 28rem)`. On iPhone the board should fill the width minus safe-area padding, pinned near the top, with all controls in the bottom third — the thumb zone. Design against the smallest supported screen first (iPhone SE / mini).
- **Two input orders, both supported, chosen in Settings:**
  - *Cell-first* (web parity): tap a cell, then a digit.
  - *Digit-first*: tap a digit to arm it, then tap cells to place it. Much faster for filling many of the same digit, and the mode most competitive Sudoku apps default to.
- **Pencil mode**: a toggle button, plus long-press on a numpad key as a one-shot pencil entry without changing modes.
- **Blind mode**: long-press a filled cell (the web already uses a 450 ms long-press for exactly this — port the timing).
- **Highlight digit**: double-tap a filled cell (web parity), and auto-highlight on numpad selection in digit-first mode.
- **Undo/redo**: dedicated buttons, plus device-shake-to-undo disabled (it fires accidentally).
- **Bottom control bar**: Undo · Redo · Erase · Pencil · Hint, then the 1–9 pad below it with per-digit remaining counts (an upgrade on the web's binary complete/incomplete dimming — showing "3 left" under each digit is standard and genuinely useful).

### 3.7 State management

`@Observable final class GameSession` replaces `useGameBoard` + `useGameTimer` +
`useGamePersistence`. It owns board, given mask, pencil, selection, modes, undo
stack, timer, hints used, and completion state; it exposes intent methods
(`select`, `input`, `erase`, `undo`, `hint`, `pause`) and publishes derived
values (`conflictCells`, `completeDigits`, `unitHighlights`) as computed
properties memoised on a board-version counter.

Autosave: debounce ~1 s after any mutation, plus a forced flush on
`scenePhase` change — the web app's `useGamePersistence` debounce logic is the
reference.

---

## 4. Feature specifications

### 4.1 Difficulty ladder

Ship the three web tiers plus two more that the technique rater makes nearly
free, since users expect five:

| Name | Tier band | Min clues |
|---|---|---|
| Easy | 1–2 | 34 |
| Medium | 3 | 30 |
| Hard | 3–4 | 26 |
| Expert | 4 | 22 |
| Evil | 4 (maximal carve, no clue floor) | 17 |

"Evil" is the existing hard spec with `minClues` dropped to the theoretical
minimum, so it stays logic-solvable — no guessing tier is ever shipped.

### 4.2 Hints — a genuine upgrade over the web app

The web app can only ask the server "what goes in this cell?". With the full
technique solver on-device, hints can *teach*:

1. **Nudge** — "There's a hidden single in box 4."
2. **Locate** — highlight the relevant unit and candidates.
3. **Explain** — "Only R5C2 in this box can be a 7, because 7 is already in row 4 and row 6."
4. **Reveal** — fill the cell.

Implement `HintEngine.nextStep(board:) -> HintStep` by running the technique
solver one step at a time against the *user's current board* (not the original
puzzle), which also detects when the user has made an error that makes the
puzzle unsolvable — a "you have a mistake above this point" check that the web
app cannot do offline. Escalating hint levels means `hintsUsed` should weight by
level, not count reveals only.

### 4.3 Daily puzzle & calendar

Deterministic from the date seed (§3.3), generated lazily and cached in
SwiftData on first open. The calendar month view mirrors `CalendarPage.tsx`:
each day up to today shows unplayed / in-progress / completed. Past days are
playable — the seed makes them reproducible with no stored history.

Streak = consecutive days with a completed daily, computed locally (port
`GetStreakForUser`'s semantics). Streak is what an optional daily local
notification should protect ("your 12-day streak ends tonight") — opt-in only.

### 4.4 Stats

Port the full `StatsResponse` shape as a locally computed aggregate over
`Completion` rows: total, by difficulty, by day-of-week, by month, per-difficulty
avg/best, time-distribution buckets, current/best streak, recent completions.
Render with Swift Charts. Add a GitHub-style contribution heatmap of the last
year — the data (`by_month`, completion dates) is already there and it is the
single most motivating stats view for a daily-habit app.

### 4.5 Achievements

`achievements.go`'s `CheckNew` is a pure function over
`(difficulty, timeSeconds, totalFinished, currentStreak, alreadyEarned)` — port
it verbatim into `SudokuKit`, tests included. Keep the 11 existing keys so a
future sync can reconcile with the web app's `user_achievements` table. Add an
unlock animation and an achievements grid in Stats.

### 4.6 Manual puzzle import

Port `ImportPage.tsx`: an 81-cell entry grid, min 17 givens, then validate with
`countSolutions(g, 2) == 1` and reject non-unique or contradictory input. On
device, additionally run `Rate()` and tell the user the difficulty they've just
entered — a nice touch the web version doesn't offer. **No OCR** (§1.4).

### 4.7 Sharing without a server

Replace slug URLs with a self-contained code: the 81-digit puzzle string,
base-64-ish encoded to ~55 characters, wrapped in a custom URL scheme and a
Universal Link fallback:

```
sudokuandcake://p/<code>
```

Opening it imports and starts that exact puzzle. Add a "share as image" option
rendering the board — that's what actually gets sent in messages.

### 4.8 Widgets

- **Home Screen (small/medium):** today's daily — its difficulty, whether it's done, current streak. Deep-links into the daily.
- **Lock Screen (circular):** streak count. **(rectangular):** "Daily ready" / "Daily done ✓".
- Data crosses the process boundary via an **App Group** container holding a tiny `DailyStatus` snapshot written by the app on each relevant change. Do **not** try to read the SwiftData store from the widget process; write a purpose-built snapshot file.

### 4.9 Haptics & sound

`UIImpactFeedbackGenerator` light on digit placement, warning notification on
conflict, medium on unit completion, success notification on solve. Prepare
generators ahead of use to avoid first-tap latency. All muteable in Settings;
respect the silent switch for sound but not for haptics.

---

## 5. Phased plan

Each phase is a vertical slice that leaves the app runnable and demoable.

### Phase 0 — Scaffold (½ day)

Repo, `.gitignore`, `Taskfile.yml` (`install`, `build`, `test`, `lint`,
`xcodegen`, `run`), SwiftLint + swift-format configs, GitHub Actions running
`swift test` on macOS. Empty SwiftUI app launches and shows "Hello".
*Done when:* CI is green and the app runs in the simulator.

### Phase 1 — SudokuKit core (2–3 days) · *no Xcode needed*

`Grid`, `Validator`, `Solver` (backtracking + `countSolutions`), `Techniques`,
`Rater`. Port every Go test table from `generator_test.go`, `difficulty_test.go`,
`validator_test.go` into Swift Testing.
*Done when:* `swift test` passes and `Rate()` agrees with the Go implementation
on a corpus of ≥200 puzzles exported from the Go tests as a fixture file.

**Cross-check harness:** write a one-off Go program that emits
`{puzzle, tier}` pairs as JSON, commit it as a test fixture in the iOS repo.
This is the highest-value ~2 hours in the whole plan — it turns "I think the port
is right" into a proof.

### Phase 2 — Generator + tracer bullet (2–3 days)

`SeededRandom`, `Generator.generate`, `PuzzlePool` actor, bundled seed puzzles.
Minimal SwiftUI: a "New Game" button → a real generated board on screen, tap a
cell, tap a digit, the digit appears.
*Done when:* a puzzle of each difficulty generates within budget on device, and
`generate(daily: someDate)` is provably reproducible. **Benchmark here.**

### Phase 3 — Full game UX (4–5 days)

`GameSession`, `BoardView`, `NumberPad`, control bar. Pencil marks, undo/redo,
erase, restart, conflict highlighting, unit-completion celebration, complete-digit
counts, highlight-digit, blind mode, win detection + celebration. Timer with
pause and the inactivity prompt. Both input orders.
*Done when:* a puzzle is playable start to finish with feature parity to
`GamePage.tsx` minus persistence.

### Phase 4 — Persistence (2–3 days)

SwiftData models, `GameRepository`, debounced autosave, resume-on-launch, saved-
games list with swipe-to-delete, completion recording.
*Done when:* force-quitting mid-game and relaunching restores board, pencil,
elapsed time, and hint count exactly.

### Phase 5 — Daily & calendar (2 days)

Deterministic daily, calendar month view with per-day state, streak computation,
opt-in streak notification.
*Done when:* two simulators on the same date get the same daily, and past dates
are playable.

### Phase 6 — Stats & achievements (2–3 days)

Aggregate queries, Swift Charts views, year heatmap, achievements engine + grid
+ unlock animation.
*Done when:* every field of the web `StatsResponse` has a local equivalent
rendered.

### Phase 7 — Hints & settings (2–3 days)

`HintEngine` with escalating levels and mistake detection. Settings screen:
theme, error highlighting, inactivity timeout, input mode, auto-pencil, haptics,
sound, notifications.
*Done when:* the hint engine explains a locked-candidate and an X-wing step in
plain language on a real puzzle.

### Phase 8 — Widgets, haptics, polish (3–4 days)

App Group + `DailyStatus` snapshot, three widget families, haptic and sound
layer, app icon, launch screen, transitions, empty states, onboarding.

### Phase 9 — Accessibility & release (2–3 days)

VoiceOver over the grid (each cell announcing "row 3, column 5, empty" /
"…contains 7, given"), a custom rotor for row/column/box navigation, Dynamic Type
to at least XXL without clipping, Reduce Motion honoured for the celebration
animations, colour-blind-safe conflict indication (never colour alone — pair it
with a shape or underline). Privacy manifest (`PrivacyInfo.xcprivacy`) declaring
no tracking and no data collection — trivially true here, and it makes for the
strongest possible App Store privacy label. Screenshots, metadata, TestFlight.

**Total: roughly 4–5 focused weeks** to a submittable v1.

---

## 6. Testing strategy

- **SudokuKit**: Swift Testing, ported Go test tables, plus the Go↔Swift tier cross-check fixture (Phase 1). Property tests: every generated puzzle has exactly one solution; every generated puzzle rates within its spec band; `Rate` never returns `TierBeyond` for a generated puzzle.
- **Performance**: `swift-testing` benchmarks with explicit budgets per difficulty, run in CI so a refactor that triples carve cost fails the build rather than shipping.
- **GameSession**: unit-tested headlessly — input, undo/redo, conflict derivation, completion — no view rendering needed.
- **Persistence**: in-memory `ModelContainer`, round-trip tests for save/restore.
- **UI**: a thin XCUITest smoke suite (launch → new game → place a digit → background → relaunch → state restored). Keep it small; XCUITests are slow and flaky at volume.
- **Snapshot tests** for `BoardView` in light/dark and at the largest Dynamic Type size.

---

## 7. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Generation too slow on older iPhones | Spinner on "New game" — the worst possible first impression | Benchmark in Phase 2, not Phase 8. Bundled seed puzzles + disk-persisted pool + background refill. Fallback: lower `attempts` and accept the closest tier (path already exists in the Go code). |
| Technique-solver port has a subtle bug | Puzzles mis-rated; "easy" that needs an X-wing | The Go↔Swift cross-check fixture in Phase 1. Non-negotiable. |
| Allocation pressure in the carve loop | Generation far slower than Go despite similar algorithm | Value-type `Grid`, bitmask instead of `map` in `nakedSubsets`, `Instruments` pass in Phase 2. |
| SwiftData schema churn | Migration pain post-launch | Freeze the schema at the end of Phase 4; treat it as CloudKit-shaped from day one so sync never forces a migration. |
| Scope creep from the web app's 983-line GamePage | Phase 3 balloons | Phase 3 has a named parity list; anything not on it goes to a backlog file. |
| No Xcode installed | Phases 3+ blocked | Install full Xcode before Phase 3. Phases 1–2 proceed on the CLI toolchain today. |

---

## 8. Open questions to settle before Phase 3

1. **Minimum iOS version.** iOS 17 unlocks SwiftData and `@Observable` and covers ~95% of active devices; iOS 18 adds nicer widget APIs. Recommendation: **iOS 17**.
2. **iPad.** Universal from day one is cheap if the layout is adaptive from the start and expensive to retrofit. Recommendation: **build layouts adaptively, ship iPhone-only, enable iPad in a fast follow.**
3. **Monetisation.** Free with no ads is the honest fit for a local-only app with no server cost. If revenue matters, a one-off "unlimited hints + themes" IAP is the least user-hostile option. Needs deciding before App Store metadata, not before code.
4. **Name and bundle ID.** Reusing "Sudoku and Cake" keeps brand continuity with the web app and makes a future sync feature coherent.
