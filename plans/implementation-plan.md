# Sudoku and Cake for iOS — Detailed Implementation Plan

Companion to [`sudoku-ios.md`](./sudoku-ios.md), which sets the strategy. This
document is the build sheet: concrete file layout, type signatures, measured
performance budgets, a task-by-task breakdown with acceptance criteria, and the
adaptive-layout spec for iPhone **and** iPad.

Reference implementation: `../sudoku-and-cake` (Go backend + React frontend).
Every port target below cites the exact source file and function.

---

## 0. Scope, and where this differs from `sudoku-ios.md`

Decisions carried over unchanged: fully local (no accounts, no sync, storage kept
CloudKit-shaped), deterministic on-device dailies, technique-based difficulty
ported faithfully, WidgetKit + haptics in v1, no Game Center / Watch / OCR.

Four deltas, all driven by new information:

| # | Change | Why |
|---|---|---|
| D1 | **iPhone *and* iPad ship together in v1** (was: iPhone-only, iPad as fast-follow) | Explicit product scope. Cost is ~3–4 days if adaptive layout is designed in from Phase 3; retrofitting later costs far more. |
| D2 | **Hardware-keyboard shortcuts are back in scope** | §1.4 of the strategy doc deferred them "only if an iPad build ever happens". It now happens. iPad + Magic Keyboard is a first-class way to play, and the bindings already exist in `useGameBoard.ts:322-389`. |
| D3 | **Deployment target iOS 18, built against the current SDK** (was: iOS 17) | The strategy doc's iOS 17 recommendation predates the current date (Aug 2026). iOS 17 is three releases old; iOS 18 costs nothing in reach, and building against the current SDK with stock SwiftUI controls means the app adopts the current system design language for free. See §12-Q1 — this is the one call worth confirming. |
| D4 | **The pool is a warm cache, not a load-bearing dependency** | Measured generation cost (§3) is an order of magnitude below the strategy doc's estimate. The pool still earns its place as latency polish, but "New game" no longer needs bundled seed puzzles to avoid a spinner. |

---

## 1. Toolchain — verified on this machine, today

| Tool | State |
|---|---|
| Swift | 6.3.3 (`swiftlang-6.3.3.1.3`), target `arm64-apple-macosx26.0` |
| Xcode | **26.6 (17F113), installed and selected.** Phase 3 is unblocked. |
| XcodeGen | `/opt/homebrew/bin/xcodegen` ✓ |
| SwiftLint | `/opt/homebrew/bin/swiftlint` ✓ |
| swift-format | `/opt/homebrew/bin/swift-format` ✓ |
| Task | `~/workspace/go/bin/task` ✓ |
| Go | 1.26.5 (needed for the cross-check fixture exporter, §5.3) |

**Consequence, and the reason the architecture is shaped this way:** Phases 0–2
— the entire game engine, generator, rater, hint engine and their tests — build
and run under plain `swift test` on the command line. That mattered: the whole
engine was written and verified before Xcode existed on this machine.

**Two prerequisites, not one.** Installing Xcode is necessary but not
sufficient, and conflating them broke `task test`: the app tasks were guarded on
Xcode alone, so the moment it appeared they started running and XcodeGen
rejected a spec whose source directories do not exist yet.
`scripts/skip-app-tasks.sh` is the single guard — XcodeGen present, Xcode
usable, *and* `SudokuApp/Sources` non-empty — used by every app task's
`status:`. It lives in a script because Task parses `status:` with its own
shell, which does not evaluate a `! a || ! b` chain the way bash does; the
inline version reported "not up to date" and ran anyway.

**Three CLT-only quirks, resolved in `Taskfile.yml`.** They no longer bite on
this machine, but the Taskfile computes them so a contributor with only Command
Line Tools still gets a working `task test:kit`:

- SwiftPM sandboxes manifest evaluation with `sandbox-exec`, which cannot nest
  inside an outer sandbox. `--disable-sandbox` fixes it and is safe: this package
  has no dependencies and no build plugins.
- Swift Testing *ships* with the CLT but SwiftPM does not wire up its search
  paths, so `import Testing` fails to compile and then fails to load. It needs
  `-F` plus rpaths to both `…/Library/Developer/Frameworks` and
  `…/Library/Developer/usr/lib` (for `lib_TestingInterop.dylib`). The Taskfile
  computes these and emits nothing once Xcode is present.
- SwiftLint loads `sourcekitd`, which it looks for inside Xcode.
  `DYLD_FRAMEWORK_PATH=/Library/Developer/CommandLineTools/usr/lib` points it at
  the CLT copy.

`sudoku-ios/` is already a git repo containing `LICENSE` and an Xcode
`.gitignore`. Everything below is new.

---

## 2. Repo layout

```
sudoku-ios/
├── Taskfile.yml                  # install · build · test · lint · format · xcodegen · run · bench
├── .swiftlint.yml
├── .swift-format
├── .github/workflows/ci.yml
├── Package.swift                 # SudokuKit only — buildable without Xcode
├── SudokuKit/
│   ├── Sources/SudokuKit/
│   │   ├── Grid.swift              # value type over 81 UInt8
│   │   ├── CellRef.swift           # row/col/index/box helpers, Unit + UnitRef
│   │   ├── Units.swift             # the 27 precomputed units
│   │   ├── Validator.swift         # port of validator/validator.go
│   │   ├── Solver.swift            # solve + countSolutions (MRV)
│   │   ├── CandidateGrid.swift     # [UInt16] masks + eliminatePeers
│   │   ├── Techniques.swift        # naked/hidden singles, locked, subsets, X-wing
│   │   ├── Rater.swift             # Tier + Rate()
│   │   ├── Difficulty.swift        # the 4-rung ladder + specs
│   │   ├── Generator.swift         # generateSolution + carveToTier
│   │   ├── SeededRandom.swift      # SplitMix64 + our own shuffle/bounded draw
│   │   ├── DailyPuzzle.swift       # date → seed → puzzle
│   │   ├── HintEngine.swift        # NEW: technique-explaining hints
│   │   ├── ShareCode.swift         # compact puzzle encoding
│   │   ├── Achievements.swift      # port of achievements/achievements.go
│   │   ├── Streak.swift            # port of store.GetStreakForUser semantics
│   │   ├── StatsAggregator.swift   # port of store.GetStatsForUser shape
│   └── Tests/SudokuKitTests/
│       ├── Fixtures/tier-corpus.json      # generated by tools/export-fixtures (Go)
│       ├── Fixtures/known-puzzles.json    # hand-picked edge cases
│       ├── GridTests.swift · SolverTests.swift · RaterTests.swift
│       ├── TechniqueTests.swift · GeneratorTests.swift
│       ├── DeterminismTests.swift · CrossCheckTests.swift
│       ├── HintEngineTests.swift · ShareCodeTests.swift
│       ├── AchievementsTests.swift · StreakTests.swift · StatsTests.swift
│       └── PerformanceTests.swift
├── SudokuApp/
│   ├── project.yml                # XcodeGen; .xcodeproj is gitignored
│   ├── Resources/
│   │   ├── Assets.xcassets        # icon, colours, symbols
│   │   └── PrivacyInfo.xcprivacy
│   ├── Sources/
│   │   ├── App/                   # SudokuApp.swift, RootView, Router, Theme, AppEnvironment
│   │   ├── Game/                  # GameSession, BoardView, CellView, NumberPad,
│   │   │                          #   ControlBar, GameScreen, GameLayout, KeyboardCommands
│   │   ├── Daily/                 # DailyScreen, CalendarScreen, CalendarModel
│   │   ├── Stats/                 # StatsScreen, Charts, Heatmap, AchievementsGrid
│   │   ├── Import/                # ImportScreen, ImportGrid
│   │   ├── Settings/              # SettingsScreen, AppSettings (@AppStorage)
│   │   ├── Persistence/           # SwiftData models, GameRepository, SwiftDataRepository
│   │   └── Services/              # Haptics, Sound, Notifications,
│   │                              #   SharedSnapshot (App Group), DeepLinkHandler
│   └── Tests/
│       ├── SudokuAppTests/        # GameSession, repository, settings — headless
│       └── SudokuAppUITests/      # thin XCUITest smoke suite
├── SudokuWidgets/
│   ├── SudokuWidgets.swift · DailyWidget.swift · StreakWidget.swift
│   └── Provider.swift             # reads the App Group snapshot only
└── tools/
    └── export-fixtures/main.go    # Go program producing tier-corpus.json
```

`project.yml` is checked in; the generated `.xcodeproj` is not. `task xcodegen`
regenerates it, and CI regenerates before building.

---

## 3. Measured performance baseline and budgets

Benchmarked today against `sudoku-and-cake/backend/internal/generator` on this
machine (Apple M5, Go 1.26.5). 40 samples per difficulty of the full
`Generate(difficulty)` call, retries included:

| Difficulty | p50 | p90 | max | mean (`go test -bench`) |
|---|---|---|---|---|
| easy | 420 µs | 573 µs | 641 µs | 1.17 ms |
| medium | 7.5 ms | 22.7 ms | 39.4 ms | 15.3 ms |
| hard | 44.8 ms | 160 ms | 237 ms | 61.5 ms |

This is materially cheaper than the strategy doc's "80 attempts × 70 ms ≈ 5.6 s"
worst case — because `Generate` returns on the *first* in-band puzzle, and the
hit rate is far better than the pessimistic estimate.

Scaling to the oldest device worth supporting (A12 / iPhone XR, roughly 3.5×
slower single-core than M5) and allowing 2× for a first-pass Swift port that has
not yet been profiled:

| | Go on M5 (measured) | Swift on A12 (projected worst case) | **Budget** |
|---|---|---|---|
| easy | 0.6 ms | ~4 ms | ≤ 20 ms |
| medium | 39 ms | ~275 ms | ≤ 400 ms |
| hard | 237 ms | ~1.7 s | ≤ 2.0 s |
| expert | — | — | ≤ 4.0 s |

**Gate G1 — PASSED.** Measured with `task bench` on the same machine, release
build, via `PerformanceTests.swift`:

| Difficulty | Go p50 | **Swift p50** | Go p90 | **Swift p90** | Ratio (p50) |
|---|---|---|---|---|---|
| easy | 420 µs | **233 µs** | 573 µs | **344 µs** | 0.55× |
| medium | 7.5 ms | **3.3 ms** | 22.7 ms | **12.8 ms** | 0.44× |
| hard (Go) ↔ **expert** (ours — identical spec) | 44.8 ms | **7.9 ms** | 160 ms | **26.8 ms** | 0.18× |
| hard (ours, tier 3–4) | — | 1.8 ms | — | 2.5 ms | — |

The gate was "Swift within 2× Go". Swift is **faster than Go on every
comparable rung** — 5× at the expert/hard end. The allocation discipline in §4.1
is why: `borrowing` parameters, `withUnsafeTemporaryAllocation` scratch, and the
bitmask that replaced Go's per-combination `map` in `nakedSubsets`.

Per-call cost of the two hot functions inside the carve loop, on hard puzzles:
`rate` p50 72 µs, `countSolutions` p50 130 µs.

Consequence for §6.3: at these speeds **every difficulty can generate inline**
within the budget even after a 3.5× slowdown for an A12. The pool becomes a
latency polish rather than a correctness requirement, and the bundled seed set
(P2-7) drops to a nice-to-have.

**Gate G2 — Phase 2, on device.** Re-measure on the oldest available hardware
against the budget column. Mitigations in preference order: (1) lower `attempts`
and accept the closest in-ceiling match — the fallback path already exists in
`generator.go:142-145`; (2) widen the bundled seed set; (3) reduce the ladder.

---

## 4. SudokuKit — the port

Dependency-free, `Sendable` throughout, no Foundation in the hot paths, no
UIKit. Every public type is a value type.

### 4.1 Core representation

```swift
public struct Grid: Equatable, Hashable, Sendable {
    // 81 cells, row-major, 0 = empty. ContiguousArray for a stable layout.
    @usableFromInline internal var cells: ContiguousArray<UInt8>

    public init()                                   // empty
    public init?(digits: String)                    // 81 chars, '0'/'.' = empty
    public subscript(row: Int, col: Int) -> Int { get set }
    public subscript(index: Int) -> Int { get set }

    public var clueCount: Int { get }
    public var isFull: Bool { get }
    public func digits() -> String                  // 81-char canonical form
}

public struct CellRef: Equatable, Hashable, Sendable {
    public let index: Int                           // 0..80
    public var row: Int { index / 9 }
    public var col: Int { index % 9 }
    public var box: Int { (row / 3) * 3 + col / 3 }
}

public enum UnitRef: Equatable, Hashable, Sendable {
    case row(Int), column(Int), box(Int)
    public var cells: [CellRef] { get }             // from the precomputed table
}
```

`Units.allUnits: [[CellRef]]` is the direct analogue of `buildUnits()`
(`difficulty.go:30-58`) — 27 units, computed once as a `static let`.

**Allocation discipline.** Go's `Grid` is `[9][9]int`, a fixed array copied by
value for free. Swift's `ContiguousArray` is heap-allocated with COW, and
`carveToTier` copies the grid thousands of times. Three rules:

1. Hot functions take `borrowing Grid` and never copy it.
2. Solver and rater scratch space uses
   `withUnsafeTemporaryAllocation(of:capacity:)` — stack-allocated, no ARC, no
   allocator traffic, and available on every deployment target we care about.
   Deliberately *not* `InlineArray`, whose back-deployment story to iOS 18 is a
   risk we do not need to take.
3. Techniques operate on an `UnsafeMutableBufferPointer<UInt16>` of 81
   candidate masks handed down from the rater, never on their own copy.

### 4.2 Techniques and rater

Line-by-line ports of `difficulty.go`:

| Go | Swift | Notes |
|---|---|---|
| `techSolver` (l.61) | `struct TechniqueSolver` over borrowed buffers | |
| `eliminatePeers` (l.90) | same | |
| `stuck` (l.112) | same | |
| `Rate` (l.130) | `Rater.rate(_ puzzle: borrowing Grid) -> Tier` | Preserve the cheapest-first loop order **exactly** — it decides the reported tier. |
| `nakedSingles` (l.165) | same | `bits.OnesCount16` → `.nonzeroBitCount`, `bits.TrailingZeros16` → `.trailingZeroBitCount` |
| `hiddenSingles` (l.182) | same | |
| `lockedCandidates` (l.211) | same | pointing + claiming, both directions |
| `nakedSubsets(k)` (l.316) | same, **one deliberate change** | Go builds `map[[2]int]bool` per combination (l.338). Replace with a `UInt16` bitmask of unit-relative indices. Identical semantics, zero allocation — in Swift the map would dominate the profile. |
| `hiddenSubsets(k)` (l.361) | same | already bitmask-based |
| `xWing` (l.415) | same | rows and columns |
| `forEachCombination` (l.493) | recursive closure over a reused `pick` buffer | keep allocation-free |

```swift
public enum Tier: Int, Comparable, Sendable, CaseIterable {
    case nakedSingle = 1, hiddenSingle = 2, locked = 3, advanced = 4, beyond = 5
}
public enum Rater { public static func rate(_ puzzle: borrowing Grid) -> Tier }
```

### 4.3 Solver

Ports `Solve`, `solveDeterministic`, `countSolutions`, `findBestEmptyCell`,
`candidatesFor` (`generator.go:45-309`). `findBestEmptyCell` is MRV — keep it,
it is why `countSolutions` is fast enough to run per removal attempt.

```swift
public enum Solver {
    public static func solve(_ puzzle: borrowing Grid) -> Grid?
    public static func countSolutions(_ puzzle: borrowing Grid, limit: Int) -> Int
    public static func hasUniqueSolution(_ puzzle: borrowing Grid) -> Bool  // == 1
}
```

Note the Go recursion at `generator.go:247` passes `limit-count`, not `limit`.
Port that arithmetic verbatim; it is the early-exit that keeps the count cheap.

### 4.4 Determinism

Go's `math/rand` and Swift's RNG differ, so byte-identical dailies with the web
app are not achievable — and with sync off, not required. What *is* required is
that every iOS device agrees.

```swift
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64)
    public mutating func next() -> UInt64          // SplitMix64
}
```

**Two traps to avoid, both of which would silently reshuffle everyone's daily
history on a future Swift release:**

- Do **not** use `Array.shuffle(using:)`. Its implementation is not a documented,
  stable algorithm. Implement `deterministicShuffle(using:)` — plain Fisher-Yates,
  descending, drawing from our own bounded generator.
- Do **not** use `Int.random(in:using:)`. Implement `nextBounded(_:)` with
  Lemire's rejection method inside `SeededRandom`.

Every draw in `generateSolution` and `carveToTier` threads an injected
`inout SeededRandom`. **No call to the global RNG anywhere in SudokuKit** —
enforced by a SwiftLint custom rule matching `\.random\(|randomElement\(|shuffled?\(`
that does not end in `using:`.

```swift
public enum DailyPuzzle {
    /// Seed = UTC-midnight epoch seconds for `date`, matching slug.GenerateForDate.
    public static func seed(for date: Date) -> UInt64
    public static func generate(for date: Date) -> GeneratedPuzzle
    public static func dateKey(for date: Date) -> String   // "YYYY-MM-DD", UTC
}
```

Tested three ways: same date twice → equal; a golden-value test pinning ~10
known dates to their exact 81-char puzzle strings so an accidental algorithm
change fails the build; and a spread test asserting 365 consecutive dates
produce 365 distinct puzzles.

### 4.5 Difficulty ladder

Three web tiers (`generator.go:24-31`) plus two the rater makes nearly free:

```swift
public enum Difficulty: String, CaseIterable, Sendable {
    case easy, medium, hard, expert
}

// minTier, maxTier, minClues, attempts
easy:   (.nakedSingle, .hiddenSingle, 34, 10)   // web parity
medium: (.locked,      .locked,       30, 60)
hard:   (.locked,      .advanced,     26, 80)
expert: (.advanced,    .advanced,     22, 80)   // web "hard"
```

`maxTier` never exceeds `.advanced` on any rung, so **no shipped puzzle ever
requires guessing** — the differentiator, preserved.

**P2-6 — RESOLVED: Evil is dropped. The ladder ships four rungs.**

Measured, and the risk was real — Expert and Evil were the same rung:

| | median clues | p50 generation | p90 generation |
|---|---|---|---|
| Expert (floor 22) | 25 | 7.9 ms | 26.8 ms |
| Evil (floor 17) | 25 | 8.7 ms | 28.4 ms |

Identical, and for a structural reason rather than bad luck: `minClues` is a
*stop-carving floor*, and neither rung ever reaches its floor. Carving halts
earlier than that, when no further removal can keep both a unique solution and a
tier at or below `.advanced` — around 25 clues. Expert and Evil share that
ceiling, so they share the stopping point, and lowering Evil's floor from 22 to
17 changes nothing at all. As specified, they are the same generator with two
labels.

**Decision: Evil dropped.** Two labels for one generator is worse than four
honest rungs. A genuine fifth rung needs a harder *technique* in the rater — an
XY-wing or swordfish as a real tier 5 — not a lower clue floor. That remains
available as a scoped follow-on: a new technique, new fixture entries, and a
re-run of the cross-check.

**The shipped ladder, measured over 16 seeds per rung:**

| Rung | Median clues | Median realised tier | Requires |
|---|---|---|---|
| Easy | 34 | 1 | scanning only |
| Medium | 28 | 3 | locked candidates or a naked pair |
| Hard | 26 | 3 | as medium, with fewer clues; sometimes advanced |
| Expert | 25 | 4 | always a hidden pair, naked triple, or X-wing |

Hard and Expert share a technique *ceiling* and sit one clue apart, so what
separates them is `minTier`: Expert **requires** an advanced technique, Hard
merely permits one. `GeneratorTests.rungsAreDistinct` guards this by comparing
the tier puzzles actually come out at, not the spec's ceiling — comparing
ceilings would have called Hard and Expert identical, and comparing clue counts
alone would have separated them by a single clue. That test is the standing
guard against another Evil.

**Medium's clue floor is 28, not the 30 originally planned.** At 30 the carve
stops before a locked candidate is forced and misses the band 4 times in 40,
falling back to a tier-2 puzzle. Medium is also the daily difficulty, so that
meant roughly three days a month quietly easier than advertised. At 28 the hit
rate is 40/40.

### 4.6 Hint engine — the upgrade over the web app

The web app can only ask the server "what goes in this cell?"
(`GamePage.tsx:153-174`). With the technique solver on-device, hints teach.

```swift
public enum HintLevel: Int, Comparable, Sendable { case nudge, locate, explain, reveal }

public enum HintStep: Sendable {
    case nakedSingle(cell: CellRef, digit: Int)
    case hiddenSingle(cell: CellRef, digit: Int, unit: UnitRef)
    case lockedCandidate(digit: Int, box: Int, line: UnitRef, eliminates: [CellRef])
    case nakedSubset(cells: [CellRef], digits: [Int], unit: UnitRef, eliminates: [CellRef])
    case hiddenSubset(cells: [CellRef], digits: [Int], unit: UnitRef)
    case xWing(digit: Int, lines: [UnitRef], eliminates: [CellRef])
    case mistake(firstWrong: CellRef)
    case stuckBeyondTier
    case solved
}

public struct Hint: Sendable {
    public let step: HintStep
    public let highlightCells: [CellRef]
    public let highlightUnits: [UnitRef]
    public func text(at level: HintLevel) -> String
}

public enum HintEngine {
    public static func next(board: borrowing Grid,
                            solution: borrowing Grid,
                            pencil: [UInt16]?) -> Hint
}
```

**Mistake detection is exact and free**, which the strategy doc under-sells: we
always hold the solution locally (generated, or computed at import time), so a
single 81-cell diff finds the first cell that contradicts it — no need to infer
"unsolvable from here". Report it as `.mistake` *before* offering any technique
hint, since every technique hint on a corrupted board is wrong.

Cost accounting: `hintPoints` weighted by level (nudge 1, locate 1, explain 2,
reveal 3), charging only the *delta* when the user escalates on the same cell.
`hintsUsed` (reveal count) is kept alongside for continuity with the web schema.

### 4.7 Share code

No server, so no slug resolution. A self-contained code instead:

```
byte 0        version (0x01)
bytes 1..11   81-bit given mask, LSB-first (11 bytes)
bytes 12..    given digits, 4 bits each, in index order (⌈n/2⌉ bytes, n = clue count)
last 2 bytes  CRC-16
```

~34 bytes for a typical 26-clue puzzle → **46 base64url characters**.

```
sudokuandcake://p/<code>
https://sudoku.andcake.dev/p/<code>     # Universal Link fallback
```

```swift
public enum ShareCode {
    public static func encode(_ puzzle: borrowing Grid) -> String
    public static func decode(_ code: String) throws -> Grid
}
```

Opening a link imports and starts that exact puzzle. Round-trip and
corrupted-input tests are non-negotiable; a bad decode must throw, never produce
a wrong grid.

### 4.8 Achievements, streaks, stats

`achievements.go:60-88` `CheckNew` is a pure function — port verbatim, all
**11 keys unchanged** (`first_easy_solve`, `first_medium_solve`,
`first_hard_solve`, `speed_easy_5m`, `speed_medium_10m`, `speed_hard_20m`,
`games_10`, `games_50`, `games_100`, `streak_7`, `streak_30`) so a future sync
reconciles with the web `user_achievements` table.

Expert maps onto `first_hard_solve` / `speed_hard_20m` for continuity; any new
rung gets *new* keys in a v2 set rather than redefining existing ones.

`Streak.swift` ports `store.GetStreakForUser` (`store.go:499-564`) exactly,
including the two semantics that are easy to get wrong: the current streak counts
only if the most recent completion is **today or yesterday**, and days are
**UTC** days.

`StatsAggregator.swift` reproduces the `Stats` shape (`store.go:241-252`) as a
pure function over `[CompletionRecord]`: `totalFinished`, `byDifficulty`,
`byDayOfWeek`, `byMonth`, `recentCompletions`, `timeStats` (count/avg/best per
difficulty), `completionRate`, `timeDistribution` (buckets `<2m`, `2–5m`,
`5–10m`, `10–20m`, `20m+` — `store.go:279-306`), `streak`.

---

## 5. Testing strategy

### 5.1 SudokuKit — Swift Testing

Ported Go tables from `difficulty_test.go`, `generator_test.go`,
`validator_test.go`, plus property tests:

- every generated puzzle has exactly one solution;
- every generated puzzle rates inside its spec band;
- `rate` never returns `.beyond` for a generated puzzle;
- solving a generated puzzle yields its stored solution;
- `Grid(digits:)` ∘ `digits()` is the identity.

Coverage target: **≥ 90 % for SudokuKit**, enforced in CI. It is pure logic with
no I/O; anything less means untested branches in the rater.

### 5.2 GameSession — headless

Input, undo/redo, pencil toggling, conflict derivation, unit completion, win
detection, timer, autosave debounce. No view rendering, so these run fast and in
`swift test` once the app target exists.

### 5.3 The Go↔Swift cross-check fixture

The highest-value few hours in the plan: it converts "I think the port is right"
into a proof, and it is the only defence against the failure mode that matters
most — a subtly mis-rated puzzle shipping as the wrong difficulty.

`tools/export-fixtures/main.go` (a small program in *this* repo, importing the
web repo's generator package via a `replace` directive) emits:

```json
[ { "puzzle": "<81 chars>", "tier": 3, "solutions": 1, "clues": 28 }, ... ]
```

Contents — **≥ 300 entries**:
- 40 puzzles per difficulty straight from `Generate` (120);
- 120 randomly carved grids across the full clue range 17–60, unfiltered, so
  `beyond` is well represented;
- 40 partially-solved boards (a generated puzzle with 10–40 extra cells filled
  from its solution), which is what the *hint engine* actually rates at runtime;
- ~20 hand-picked edge cases: a solved grid (tier 1), an empty grid, a
  contradictory grid (tier 5), known 17-clue minimal puzzles, and the four
  puzzles already embedded in `difficulty_test.go` / `generator_test.go`.

`CrossCheckTests.swift` asserts `Rater.rate` and `Solver.countSolutions` agree
with the Go values on every entry. The fixture is committed, so it also acts as
a regression corpus if the rater is ever touched.

### 5.4 Performance

`PerformanceTests.swift` runs the same distribution harness used for the Go
baseline and asserts explicit p50/p90 budgets per difficulty (§3). Run in CI so a
refactor that triples carve cost fails the build instead of shipping. Budgets are
set against the CI runner, with the device budgets checked manually at G2.

### 5.5 App layer

- **Persistence**: in-memory `ModelContainer`, round-trip save/restore of board,
  pencil, elapsed time, hint count.
- **UI**: a deliberately thin XCUITest smoke suite — launch → new game → place a
  digit → background → relaunch → state restored; and open a share link → correct
  puzzle loads. Kept small; XCUITests are slow and flaky at volume.
- **Snapshot tests** for `BoardView`: light/dark × iPhone SE/iPad × default and
  largest Dynamic Type.

---

## 6. App architecture

### 6.1 GameSession

`@Observable final class GameSession` replaces `useGameBoard` + `useGameTimer` +
`useGamePersistence`. Behaviour ported from `useGameBoard.ts`, with these details
carried across precisely because they are what makes the web app feel right:

- Tapping the **already-selected** cell deselects it, and any selection clears
  blind mode (`useGameBoard.ts:248-254`).
- Entering the digit already in the cell **erases** it (l.286-289).
- Placing a value **clears that cell's pencil marks** (l.293-297).
- Givens are immutable — input and erase both no-op on them.
- Undo stack cap **100**, and any new mutation clears the redo stack (l.192-195).
- Unit celebration lasts **2 s**; `newlyCompleted` returns empty on the first
  computation so loading a saved board does not fire a celebration (l.87).
- Incorrectly-completed units get a distinct warning style, not the celebration.
- Conflict highlighting is **opt-in** and highlights *both* cells of a duplicate
  pair, including a given as the partner (l.468-500).
- Win detection is fully local (`isSolved`, l.78-81).

```swift
@Observable @MainActor final class GameSession {
    // State
    private(set) var board: Grid
    private(set) var given: [Bool]            // 81
    private(set) var pencil: [UInt16]         // 81 bitmasks
    var selection: CellRef?
    var inputMode: InputMode                  // .cellFirst | .digitFirst
    var armedDigit: Int?                      // digit-first
    var pencilMode: Bool
    var blindMode: Bool
    var highlightedDigit: Int?
    private(set) var elapsed: Duration
    private(set) var isPaused: Bool
    private(set) var hintPoints: Int
    private(set) var outcome: Outcome?        // .solved(time:)

    // Intents
    func select(_ cell: CellRef)
    func longPress(_ cell: CellRef)           // blind mode
    func doubleTap(_ cell: CellRef)           // highlight digit
    func input(_ digit: Int)
    func erase()
    func toggleNotes()
    func autoFillNotes()
    func undo(); func redo(); func restart()
    func requestHint(level: HintLevel) -> Hint
    func pause(); func resume()

    // Derived, memoised on a boardVersion counter
    var conflicts: Set<CellRef> { get }
    var digitCounts: [Int] { get }            // remaining per digit, 1...9
    var unitHighlights: UnitHighlights { get }
    var isSolved: Bool { get }
}
```

Autosave: debounced ~1 s after any mutation, plus a forced flush on `scenePhase`
change — `useGamePersistence.ts` is the reference for the debounce shape.

### 6.2 Persistence

SwiftData, **CloudKit-shaped from day one** even though sync is off: no
`@Attribute(.unique)`, every property optional or defaulted, all relationships
optional and inverse-declared. Flipping
`ModelConfiguration(cloudKitDatabase: .private)` later then costs one line rather
than a migration.

```swift
@Model final class PuzzleRecord {
    var id: UUID?
    var puzzle: Data?            // 81 bytes
    var solution: Data?          // 81 bytes
    var difficultyRaw: String?
    var tier: Int?
    var sourceRaw: String?       // generated | daily | imported | shared
    var dateKey: String?         // "YYYY-MM-DD" for dailies, else nil
    var createdAt: Date?
}

@Model final class SavedGame {
    var puzzleID: UUID?
    var board: Data?             // 81 bytes
    var pencil: Data?            // 162 bytes — 81 × UInt16, little-endian
    var elapsedSeconds: Int?
    var hintsUsed: Int?
    var hintPoints: Int?
    var updatedAt: Date?
}

@Model final class Completion {
    var puzzleID: UUID?
    var difficultyRaw: String?
    var timeSeconds: Int?
    var hintsUsed: Int?
    var completedAt: Date?
}

@Model final class AchievementRecord {
    var key: String?
    var unlockedAt: Date?
}
```

Pencil marks are `UInt16` bitmasks, not `[[Int]]` — smaller, and identical to the
solver's representation, so no conversion at the hint boundary.

Everything goes through `protocol GameRepository` so views never touch a
`ModelContext`, tests use an in-memory implementation, and a sync provider can be
layered in later.

Settings live in `@AppStorage`, mirroring `lib/settings.ts`: inactivity minutes
(1/3/5/10, default 5), error highlighting (default **off**, matching the web),
theme, haptics, sound, input mode, auto-pencil, notification opt-in.

### 6.3 PuzzlePool

```swift
public actor PuzzlePool {
    public func take(_ difficulty: Difficulty) async -> GeneratedPuzzle
    public func refill() async
    public func prime(with puzzles: [GeneratedPuzzle])
    public func save() throws -> Bool
    public func restore() -> Int
    public func clear()
}
```

**Built, and it lives in `SudokuKit`, not `SudokuApp/Services/`.** It is pure
logic plus file I/O with no UIKit, so keeping it in the package means it is
testable with `swift test` today rather than waiting on Xcode — the same reason
the engine is a package at all.

Ports `pool.go`'s idea — a warm buffer — with four phone-specific changes:

1. **`take` never waits.** `pool.go` blocks callers until a background filler
   produces something, because bounding CPU across many concurrent requests
   matters more than any one request's latency. A phone has one user, already
   looking at the screen, so an empty buffer means generate *now* — which Gate
   G1 makes affordable.
2. **Target depth 3 per rung**, not the server's 16. One user, one game at a
   time.
3. **The buffer persists to disk**, so a cold launch starts warm. Every read
   failure — missing file, corrupt data, an entry that no longer parses —
   degrades to "start empty": a cache that can fail a launch is worse than no
   cache.
4. **Refills respect thermal and battery state**, pausing under Low Power Mode
   or `thermalState >= .serious`. That check governs speculative work only; a
   `take` the player asked for always proceeds.

Generation runs in a **detached task rather than inside the actor**. Carving is
solid CPU work, and doing it on the actor would block every other message —
including the `take` a player is waiting on. `PuzzlePoolTests` asserts that
property directly rather than trusting the comment.

Because Gate G1 demoted generation from a latency risk to a rounding error, the
bundled seed set (P2-7) is now a nice-to-have rather than a requirement;
`prime(with:)` is the hook for it if it is ever wanted. Dailies bypass the pool
entirely — they are seeded and cached in SwiftData on first open.

### 6.4 Services

- `Haptics` — `UIImpactFeedbackGenerator(.light)` on placement, `.warning`
  notification on conflict, `.medium` on unit completion, `.success` on solve.
  Generators are `prepare()`d on screen appear to avoid first-tap latency.
  Muteable in Settings; haptics ignore the silent switch, sound respects it.
- `SharedSnapshot` — writes a tiny `DailyStatus` JSON into the App Group
  container (`group.dev.andcake.sudoku`) on every relevant change. The widget
  process reads **only** this file and never touches the SwiftData store.
- `Notifications` — one opt-in local notification protecting the streak
  ("your 12-day streak ends tonight"), scheduled for a user-chosen hour, cancelled
  the moment the day's daily is completed.
- `DeepLinkHandler` — `sudokuandcake://p/<code>` plus the Universal Link.

---

## 7. Design system

The web app's tokens (`frontend/src/index.css`) are a complete, considered
light/dark pair. Port them verbatim into an asset catalog with light/dark
variants so the two apps stay visually related.

| Token | Light | Dark | Use |
|---|---|---|---|
| `page` | `#ffffff` | `#0a0a0a` | screen background |
| `surface` | `#ffffff` | `#171717` | cell background |
| `surfaceRaised` | `#fafafa` | `#262626` | numpad keys, cards |
| `surfaceInset` | `#f5f5f5` | `#262626` | erase key |
| `surfaceBlocked` | `#d4d4d4` | `#404040` | blind-mode masked cells |
| `fg` / `fgStrong` | `#262626` / `#262626` | `#e5e5e5` / `#f5f5f5` | entries / givens |
| `fgFaint` | `#737373` | `#a3a3a3` | pencil marks |
| `border` / `borderStrong` | `#e5e5e5` / `#d4d4d4` | `#404040` / `#404040` | thin / box grid lines |
| `accent` / `accentBg` | `#4f46e5` / `rgba(238,242,255,.6)` | `#a5b4fc` / `rgba(49,46,129,.3)` | user entries, selection |
| `focus` | `#6366f1` | `#818cf8` | selection ring |
| `error` / `errorBg` | `#dc2626` / `rgba(254,242,242,.6)` | `#f87171` / `rgba(127,29,29,.2)` | conflicts |
| `success` / `successBg` | `#047857` / `#ecfdf5` | `#6ee7b7` / `rgba(6,78,59,.3)` | complete digits, celebration |
| `infoBg` | `rgba(219,234,254,.6)` | `rgba(30,58,138,.3)` | highlighted digit |

Cell celebration animation: 2 s ease-in-out, green fading through peak opacity
0.35 (light) / 0.45 (dark) — `index.css:222-236`. Gated on Reduce Motion, which
substitutes a static tint.

**Colour is never the only signal.** Conflicts get a colour *and* an underline;
complete units get a colour *and* a subtle border. Required for colour-blind
users and checked in Phase 9.

---

## 8. Adaptive layout — iPhone and iPad

The web app is keyboard-first with a mouse fallback. Neither is the primary input
here, but on iPad both may be present. Three layouts, chosen by size class.

### 8.1 Compact width (iPhone portrait, iPad Slide Over)

Board pinned near the top, all controls in the bottom third — the thumb zone.

```
┌──────────────────────────┐
│  ‹  Medium   12:34   ⏸ ⋯ │   toolbar
├──────────────────────────┤
│                          │
│      9 × 9 board         │   width − 16pt padding, max 560pt
│                          │
├──────────────────────────┤
│  ↶   ↷   ⌫   ✎   💡     │   control bar, 44pt targets
│  1 2 3 4 5 6 7 8 9       │   numpad, remaining count under each
└──────────────────────────┘   safe-area inset
```

Designed against **iPhone SE (375 × 667)** first: board 343 pt → 38 pt cells;
numpad nine keys at 36 pt with 4 pt gaps = 356 pt, fits. Everything larger scales
up from there.

### 8.2 Regular width (iPad, iPhone Pro Max landscape)

```
┌────────────┬────────────────────────┬──────────────┐
│  Sidebar   │                        │  12:34    ⏸  │
│  Play      │                        │  ↶ ↷ ⌫ ✎ 💡 │
│  Daily     │        board           │              │
│  Stats     │      (max 640pt)       │   1  2  3    │
│  Settings  │                        │   4  5  6    │
│            │                        │   7  8  9    │
└────────────┴────────────────────────┴──────────────┘
```

`NavigationSplitView` for the shell; the game screen puts the board centred with
a ~320 pt control column beside it. Board size:
`min(availableWidth − 32, availableHeight × 0.9, 640)`.

### 8.3 iPad specifics (D1)

- **Multitasking**: Slide Over and narrow Split View are compact-width — they get
  the §8.1 layout for free, but must be verified, not assumed.
- **Hardware keyboard** (D2): restore the web bindings via `.keyboardShortcut` and
  a `focusable()` grid — `1`–`9` place, `0`/`⌫` erase, arrows move, `P` notes,
  `Space` blind, `H` hint, `N` highlight, `⌘Z`/`⌘⇧Z` undo/redo, `?` help. Same
  defaults as `settings.ts:17-25`. Rebinding is v2; the defaults ship.
- **Pointer**: `.hoverEffect(.highlight)` on cells and numpad keys.
- **Menu bar commands** on iPad: Game (New, Restart, Daily), Edit (Undo, Redo),
  View (theme, highlight).
- **Multiple windows**: `WindowGroup` with per-scene `GameSession` so two puzzles
  can be open side by side. Cheap if session state is never a global singleton —
  which is the design anyway.
- Stage Manager resizing must not drop game state; covered by the smoke suite.

### 8.4 Input model

Two orders, both supported, chosen in Settings:

- **Cell-first** (web parity): tap a cell, then a digit.
- **Digit-first**: tap a digit to arm it, then tap cells. Faster for filling many
  of the same digit, and the default in most competitive Sudoku apps.

Gestures, timings ported from `Board.tsx`:

| Gesture | Action | Timing |
|---|---|---|
| Tap cell | select (tapping the selected cell deselects) | — |
| Long-press cell (filled) | toggle blind mode — masks that row and column | **450 ms** (`Board.tsx:126`) |
| Double-tap cell (filled) | highlight that digit everywhere | **300 ms** window (`Board.tsx:144`) |
| Long-press numpad key | one-shot pencil entry without leaving normal mode | 450 ms |
| Drag across cells | *not* bound in v1 — reserve for multi-select later | — |

Shake-to-undo is explicitly **disabled** (`UIApplication.applicationSupportsShakeToEdit = false`);
it fires accidentally and there are dedicated buttons.

Numpad keys show a **remaining count** under each digit ("3 left"), an upgrade on
the web's binary complete/incomplete dimming (`NumberPad.tsx:18`).

---

## 9. Work breakdown

Each phase is a vertical slice leaving the app runnable and demoable. Task IDs
are stable references for commits and issues.

### Phase 0 — Scaffold · ½ day · *no Xcode needed*

| ID | Task | Done when |
|---|---|---|
| P0-1 | `Package.swift` with the `SudokuKit` library + test target | `swift build` succeeds |
| P0-2 | `Taskfile.yml`: `install build test lint format xcodegen run bench` | `task test` runs |
| P0-3 | `.swiftlint.yml`, `.swift-format`, including the no-global-RNG custom rule | `task lint` clean |
| P0-4 | `.github/workflows/ci.yml` — `swift test` + lint on macOS | CI green |
| P0-5 | `SudokuApp/project.yml` (app + widget + test targets, App Group, URL scheme) | `task xcodegen` produces a project |
| P0-6 | `CLAUDE.md` for this repo, mirroring the web repo's | — |

### Phase 1 — SudokuKit core · 2–3 days · *no Xcode needed*

| ID | Task | Done when |
|---|---|---|
| P1-1 | `Grid`, `CellRef`, `UnitRef`, `Units` | round-trip and unit-membership tests pass |
| P1-2 | `Validator` (port of `validator.go`) | Go test table ported and green |
| P1-3 | `Solver`: solve, `countSolutions`, MRV cell choice | `generator_test.go` cases ported and green |
| P1-4 | `CandidateGrid` + `eliminatePeers` | — |
| P1-5 | Techniques: singles, locked, naked/hidden subsets, X-wing | per-technique unit tests with hand-built positions |
| P1-6 | `Rater.rate` — cheapest-first loop order preserved | `difficulty_test.go` cases green |
| P1-7 | `tools/export-fixtures/main.go` → `tier-corpus.json` (≥300 entries) | fixture committed |
| P1-8 | `CrossCheckTests` against the fixture | **100 % agreement on tier and solution count** |
| P1-9 | `PerformanceTests` harness + **Gate G1** | Swift ≤ 2× Go on this Mac, per difficulty |

*Phase done when:* `swift test` passes, SudokuKit coverage ≥ 90 %, G1 met.

### Phase 2 — Generator, determinism, tracer bullet · 2–3 days

| ID | Task | Done when |
|---|---|---|
| P2-1 | `SeededRandom` (SplitMix64) + `deterministicShuffle` + `nextBounded` | statistical smoke test; no global RNG anywhere |
| P2-2 | `Generator.generateSolution` + `carveToTier` with injected RNG | generated puzzles unique-solution and in-band |
| P2-3 | The four-rung `Difficulty` ladder | each rung rates in band, and is distinguishable from its neighbour |
| P2-4 | `DailyPuzzle` + golden-value test over ~10 pinned dates | same date → same puzzle, twice and across processes |
| P2-5 | `PuzzlePool` actor + disk persistence + thermal/battery gating | **done** — in SudokuKit, tested headlessly |
| P2-6 | Clue-count distribution for expert vs evil (§4.5 risk) | **done** — Evil dropped; `rungsAreDistinct` guards a repeat |
| P2-7 | `SeedPuzzles.bin` generator task + bundled resource | **deferred** — G1 made it unnecessary; `prime(with:)` is the hook |
| P2-8 | **Tracer bullet**: SwiftUI "New Game" → real board → tap cell → tap digit → digit appears | **done** — merged in #1; a full easy game played end to end on device |
| P2-9 | **Gate G2** on device | every difficulty inside the §3 budget |

*Needs Xcode from P2-8 onward.*

### Phase 3 — Full game UX · 5–6 days *(+1 day vs. the strategy doc, for iPad)*

**Three defects found by actually playing the tracer bullet.** They are listed
first because they are known-wrong today, not speculative polish — and because
the first is a layout bug rather than a matter of taste:

- **The board renders at roughly half the available width, centred, with a large
  gap above it.** `BoardView` wraps a `GeometryReader` in `.aspectRatio(1, .fit)`
  and then takes `min(width, height)`. Inside the `VStack` the container is
  offered more height than the square it produces, so the board ends up
  height-constrained *and* centred. Drive the cell size from width alone and let
  the grid be square on its own.
- **Number-pad glyphs clip** — 3, 5, 6, 8 and 9 lose their curves. Two `Text`s
  in a `VStack` inside a `.bordered` button, squeezed into too little height.
- **Everything else about the board is placeholder**: spacing, box-line weight
  and the givens/entries contrast were never designed, only made to work.

What was verified on device: generation, selection, digit entry, conflict
highlighting in red, and solve detection on a complete easy game.

| ID | Task |
|---|---|
| P3-0 | Fix the board sizing and number-pad clipping found in P2-8 |
| P3-1 | `GameSession` with the full intent surface and memoised derived values |
| P3-2 | `BoardView` + `CellView`: givens, entries, pencil marks, selection ring, box borders |
| P3-3 | `NumberPad` with per-digit remaining counts; `ControlBar` (undo/redo/erase/notes/hint) |
| P3-4 | Both input orders (cell-first, digit-first) |
| P3-5 | Gestures: long-press blind mode (450 ms), double-tap highlight (300 ms), long-press-key pencil |
| P3-6 | Undo/redo, cap 100, redo cleared on mutation; restart |
| P3-7 | Conflict highlighting (opt-in), unit-completion celebration (2 s) and incorrect-unit style |
| P3-8 | Win detection + celebration (confetti equivalent, Reduce Motion aware) |
| P3-9 | Timer, manual pause, inactivity prompt (1/3/5/10 min) |
| P3-10 | **Adaptive layout**: compact and regular width (§8.1, §8.2) |
| P3-11 | **iPad**: hardware keyboard commands, pointer hover, menu bar commands, multi-window |
| P3-12 | Headless `GameSession` test suite |

*Done when:* a puzzle is playable start to finish at parity with `GamePage.tsx`
minus persistence, on iPhone SE and iPad in every multitasking configuration.
**Anything not on this list goes to `plans/backlog.md`** — this is the phase that
balloons.

### Phase 4 — Persistence · 2–3 days

| ID | Task | State |
|---|---|---|
| P4-1 | SwiftData models (§6.2), CloudKit-shaped | done |
| P4-2 | `GameRepository` protocol + SwiftData and in-memory implementations | done |
| P4-3 | Debounced autosave (~1 s) + forced flush on `scenePhase` | done |
| P4-4 | Resume-on-launch; saved-games list with swipe-to-delete | done |
| P4-5 | Completion recording + achievement evaluation on solve | done |
| P4-6 | Round-trip persistence tests | done |
| P4-7 | **Freeze the schema** and record it in `plans/schema-v1.md` | done — [`schema-v1.md`](./schema-v1.md) |

*Done when:* force-quitting mid-game and relaunching restores board, pencil,
elapsed time and hint count exactly.

**Three decisions worth recording, because none of them is the obvious one:**

- **Nothing is written until the player does something.** Tapping a difficulty
  and leaving stores no row at all — the `PuzzleRecord` is written by the first
  save, not at `start`. The alternative (write the puzzle up front, sweep the
  orphans later) needs a sweep, and a sweep needs a rule for what is garbage.
- **Resume is a tap, not a redirect.** The home screen offers games in progress
  above the difficulty list; it does not drop the player back into the last
  puzzle on launch. Restoring state and choosing what to open are different
  questions, and only the first one is the app's to answer.
- **A completed puzzle is history, and history is not saved.** The saved game is
  deleted on the solve. Undoing after a win leaves a playable board that no
  longer autosaves — deliberate, since the completion is already recorded and
  re-recording it would inflate every stat that counts games.

**One bug got through, and it is worth recording how.** The first CI run failed
every UI test and never ran the unit tests at all — they are hosted in the app,
and the app was crashing at launch with a bare `SIGTRAP`, no message on stderr
and nothing in the system log. Cause: `SwiftDataRepository` stored only
`container.mainContext`, and **a `ModelContext` does not keep its
`ModelContainer` alive**. The container was a local in the function that built
the repository, so it was released on return and the next fetch trapped. It does
not reproduce while the container happens to stay in scope, which is exactly
what a naive check does. `PersistenceTests.repositoryRetainsItsContainer` builds
the repository inside a function that returns nothing else, which is the shape
that fails.

**Verification, given that `xcodebuild` cannot run inside the `nono` sandbox**
(Xcode's SwiftPM manifest evaluation calls `sandbox_apply`, which a nested
sandbox refuses — no `--allow` fixes it): everything type-checks against the iOS
18 simulator SDK under Swift 6 strict concurrency, `swiftlint --strict` and
`swift-format --strict` are clean, and the app is hand-built with `swiftc`,
installed with `simctl` and launched to confirm it reaches the home screen. The
persistence layer has no UIKit in it, so it also builds and **runs** for macOS,
where the fix was confirmed both ways: without it the same code exits 133
(SIGTRAP). `task test:app` outside the sandbox is still what runs the suites as
written.

### Phase 5 — Daily and calendar · 2 days

| ID | Task | State |
|---|---|---|
| P5-1 | Daily screen; lazy generation cached in SwiftData by `dateKey` | done |
| P5-2 | Calendar month grid: unplayed / in-progress / completed, past days playable | done |
| P5-3 | Streak computation (`Streak.swift`) surfaced in the UI | done |
| P5-4 | Opt-in streak notification with hour picker | done |

*Done when:* two simulators on the same date produce the same daily, and any past
date is playable with no stored history.

**The daily inverts Phase 4's write rule, on purpose.** A generated game stores
nothing until the player moves; a daily stores its `PuzzleRecord` the moment it
is opened. For a daily the record *is* a cache keyed by date, and it cannot
orphan — a date key is itself a reason to keep a puzzle. Determinism means the
cache is an optimisation rather than the source of truth: a store that has never
seen the 3rd of March produces the same grid as one that has, which is what
`DailyTests.sameDateSamePuzzleAcrossStores` pins down.

**Navigation became a real stack.** The game is now a route rather than a
replacement for the root, so finishing a daily returns to the calendar it was
started from. The back button and the back swipe are caught by observing the
path — nothing else tells the app a session has been left, and a session left
attached keeps autosaving from behind whatever replaced it.

**The reminder has one genuinely hard bit, and it is not the notification.** The
hour is local; the day it protects is UTC. In Newfoundland (UTC−3:30) the 10th
of August begins at 8:30 pm on the 9th, so a 7 pm reminder "for the 10th" would
fire while the app is still showing the 9th's puzzle. Fire times are therefore
clamped inside the UTC day they protect, and
`fireTimesStayInsideTheirDay` checks that across eight time zones, four dates
either side of two DST seams, and three hours.

**Verified by running, not only by type-checking.** `DailyModel`, `GameLibrary`
and `StreakReminderPlan` have no UIKit in them, so they build and run for macOS:
20 assertions covering determinism across independent stores, caching, resume,
completion, streak, the month grid and the time-zone arithmetic all pass against
the real sources. The app itself was hand-built and launched in a simulator to
confirm the new navigation reaches the home screen. What remains for CI is the
SwiftUI layer and the XCUITest flows.

### Phase 6 — Stats and achievements · 2–3 days

| ID | Task | State |
|---|---|---|
| P6-1 | `StatsAggregator` over `Completion` rows — every `StatsResponse` field | done |
| P6-2 | Swift Charts: by difficulty, by day-of-week, by month, time distribution | done |
| P6-3 | Per-difficulty avg/best, completion rate, current/best streak, recent list | done |
| P6-4 | GitHub-style year contribution heatmap | done |
| P6-5 | Achievements grid + unlock animation | done |

*Done when:* every field of the web `StatsResponse` has a rendered local
equivalent.

**One field could not be ported honestly, and is renamed rather than faked.**
The web app's `completionRate` divided by every game ever started, which a
server could count because it saw them all. Locally a game the player abandons
leaves no trace at all — deliberately, since Phase 4 writes nothing until the
first move. What *is* knowable is finished versus still open, so that is what the
tile shows and what it is called ("Finished vs. open"). Borrowing the old name
for a different denominator would have been the easy option and a lie.

**Every bar chart is a single hue.** Bar length already encodes the count;
colouring bars by their value spends the identity channel re-encoding what the
reader can already see, and colouring them by category claims four differences
that do not exist when there is one series. The heatmap is the only place colour
carries magnitude — it has no length to carry it with — so it is the only
sequential ramp, one hue light→dark, with empty days in neutral gray rather than
the palest step. Dark mode gets its own steps rather than an opacity flip.

**Three defects the tests could not have caught, found by screenshotting the
built app.** Axis labels rendered in pale blue, because `.secondary` inside a
chart is *hierarchical* and the hierarchy is the chart's foreground style — the
text was wearing the series colour. Category labels sat inside the plot on top
of the bars they named. And the first fix for that (padding the plot) moved the
marks without moving the axis, so bars stopped growing from the zero tick and
every length read high. Rendering and looking is a step, not a formality.

**Verified by running**, as in Phase 5: `StatsModel` has no UIKit, so 32
assertions over aggregation, ordering, the redefined rate and the heatmap grid
run as a macOS binary against the real sources. The screens themselves were
built and screenshotted in a simulator.

### Phase 7 — Hints, import, sharing, settings · 3–4 days

| ID | Task | State |
|---|---|---|
| P7-1 | `HintEngine` with the four escalating levels | done — engine landed in Phase 2 |
| P7-2 | Exact mistake detection against the stored solution, offered before any technique hint | done |
| P7-3 | Hint presentation: highlight cells/units, plain-language explanation, reveal | done |
| P7-4 | Manual import: 81-cell entry grid, min 17 givens, uniqueness check, **plus the rated difficulty** (a touch the web app lacks) | done |
| P7-5 | `ShareCode` encode/decode, URL scheme + Universal Link, "share as image" board render | done |
| P7-6 | Settings screen: theme, error highlighting, inactivity, input mode, auto-pencil, haptics, sound, notifications | done |

*Done when:* the hint engine explains a locked-candidate step and an X-wing step
in plain language on a real puzzle, and a shared link opens the exact puzzle on a
second device.

**Reveal did nothing for the hint that matters most.** `applyHint` guarded
`placement.digit != 0` — and a mistake hint carries exactly digit 0, meaning
"this cell should not say what it says". So the one hint a stuck player most
needs to act on was the one whose button did nothing. It erases now, and the
button says "Erase it" rather than "Fill it in".

**Settings became a model, not `@AppStorage`.** A session is built from the
input mode and the mistake setting before any view exists, and the reminder
scheduler reads the hour from a background refresh — neither is a view, and
`@AppStorage` only works in one. `AppSettings` is an `@Observable` over
`UserDefaults` that views bind to identically. The Phase 5 reminder keys are
unchanged, so an upgrade does not silently switch anyone's reminder off.

**Import rates as well as validates.** The checks run cheapest-first — rule
conflicts, then the 17-clue floor (the proven minimum for a unique solution, so
below it there is no point asking the solver), then `countSolutions(limit: 2)`,
which stops at "more than one" rather than counting. What comes back is the tier
in the vocabulary the hints use, which answers the question a player actually
has: not "is this legal" but "what am I in for".

**Two defects found by screenshotting, again.** The hint explanation for a naked
single read "R4C2 is the only digit not already in its row, column or box" — a
cell is not a digit, and the sentence describes a different technique. And the
import grid's box lines derived their *vertical* step from the view's width,
which is only correct once the square is imposed — the heavy lines were drawn
across the middle of rows.

**Verified by running:** 41 assertions over import, sharing, hint presentation,
settings and erase, run as a macOS binary against the real sources; plus the
import, hint and settings screens built and screenshotted in a simulator.

### Phase 8 — Widgets, haptics, polish · 3–4 days

| ID | Task |
|---|---|
| P8-1 | App Group + `DailyStatus` snapshot writer |
| P8-2 | Home Screen widgets (small/medium; **large on iPad** showing a mini board) |
| P8-3 | Lock Screen widgets: circular streak, rectangular "Daily ready / done ✓" |
| P8-4 | Deep links from every widget family |
| P8-5 | Haptics and sound layer, all muteable |
| P8-6 | App icon, launch screen, transitions, empty states, onboarding |

### Phase 9 — Accessibility and release · 3 days

| ID | Task |
|---|---|
| P9-1 | VoiceOver over the grid: "row 3, column 5, empty" / "…contains 7, given" |
| P9-2 | Custom rotor for row/column/box navigation |
| P9-3 | Dynamic Type to XXL with no clipping, at every layout |
| P9-4 | Reduce Motion honoured for celebrations |
| P9-5 | Colour-blind-safe conflict and completion indication (never colour alone) |
| P9-6 | `PrivacyInfo.xcprivacy` declaring no tracking and no data collection |
| P9-7 | Screenshots (iPhone **and** iPad), metadata, TestFlight build |

**Total: ~5–6 focused weeks** to a submittable universal v1 (the strategy doc's
4–5 weeks plus D1/D2).

---

## 10. CI

```yaml
# .github/workflows/ci.yml — macos-latest
jobs:
  kit:                 # runs on every push; no Xcode project needed
    - swift build -c release
    - swift test --enable-code-coverage
    - coverage gate: SudokuKit ≥ 90%
    - swiftlint --strict
    - swift-format lint --recursive --strict
  app:                 # from Phase 3 onward
    - xcodegen generate --spec SudokuApp/project.yml
    - xcodebuild test -scheme SudokuApp \
        -destination 'platform=iOS Simulator,name=iPhone 16'
    - xcodebuild test -scheme SudokuApp \
        -destination 'platform=iOS Simulator,name=iPad Pro 11-inch'
```

The `kit` job is the fast gate and covers the part of the codebase where bugs are
expensive. The `app` job runs both an iPhone and an iPad destination — with D1,
iPad is not optional.

---

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Technique-solver port has a subtle bug | Puzzles mis-rated — an "easy" that needs an X-wing | The Go↔Swift cross-check fixture, P1-7/P1-8. **Non-negotiable, and scheduled before any UI work.** |
| Allocation pressure in the carve loop | Generation far slower than Go despite the same algorithm | `borrowing` parameters, `withUnsafeTemporaryAllocation`, bitmask instead of `map` in `nakedSubsets`. Caught by Gate G1 on the CLI before Xcode is even needed. |
| ~~Generation too slow on older iPhones~~ | — | **Closed by Gate G1.** Swift is faster than Go on every rung; expert p50 is 8 ms. The pool is latency polish, not a mitigation. |
| ~~Expert and Evil feel identical~~ | — | **Confirmed and resolved.** They were identical; Evil is dropped. `GeneratorTests.rungsAreDistinct` compares realised tiers so a future rung cannot repeat it. |
| Non-reproducible dailies from an RNG change | Everyone's daily history silently reshuffles | Own the shuffle and bounded draw (§4.4); golden-value tests pin known dates; SwiftLint rule bans the global RNG. |
| SwiftData schema churn | Migration pain post-launch | Freeze at P4-7. CloudKit-shaped from day one so enabling sync never forces a migration. |
| Scope creep from the 983-line `GamePage.tsx` | Phase 3 balloons | Phase 3 has a named parity list; everything else goes to `plans/backlog.md`. |
| iPad layout retrofitted rather than designed in | Expensive rework late | P3-10/P3-11 sit inside Phase 3, not after it; CI runs an iPad destination from Phase 3. |
| No Xcode installed | Phases 2 (partly) and 3+ blocked | Install full Xcode before P2-8. Phases 0, 1 and P2-1…P2-7 proceed on the CLI toolchain today. |

---

## 12. Decisions — settled

1. **Deployment target.** **iOS 18 floor, built against the current SDK.** Stock
   SwiftUI controls then adopt the current system design language for free, while
   the floor costs nothing in reach. One line in `project.yml`
   (`deploymentTarget: iOS: "18.0"`), so it is cheap to revisit.
2. **Bundle ID and App Group.** `dev.andcake.sudoku` /
   `group.dev.andcake.sudoku`.
3. **Monetisation.** Free, no ads, no IAP. This is what makes the "no tracking,
   no data collection" privacy manifest (P9-6) trivially true.
4. **Universal Link domain.** `sudoku.ios.andcake.dev`. Keeps the iOS
   association separate from the web app's `sudoku.andcake.dev`, so an AASA file
   on the iOS subdomain cannot affect web routing. Needs
   `https://sudoku.ios.andcake.dev/.well-known/apple-app-site-association`
   serving `application/json` over TLS before P7-5. The custom scheme
   (`sudokuandcake://p/<code>`) works without it and ships regardless, so this
   is not on the critical path.
