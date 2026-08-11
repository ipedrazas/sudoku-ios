# App Store listing

Everything App Store Connect asks for, written down here so it is reviewable in
a pull request rather than typed straight into a web form and lost. The build
and upload themselves are the one part of Phase 9 that cannot be done from this
repository — see "What is not here" at the bottom.

---

## Identity

| Field | Value |
|---|---|
| Name | Sudoku and Cake |
| Subtitle | Offline Sudoku that teaches |
| Bundle ID | `dev.andcake.sudoku` |
| SKU | `dev-andcake-sudoku` |
| Primary category | Games |
| Secondary category | Puzzle |
| Age rating | 4+ |
| Price | Free |
| In-app purchases | None |

The subtitle carries the two things that separate this from the fifty other
Sudoku apps in the results: it works with no connection, and its hints explain
rather than fill in.

## Description

> Sudoku, with no account to make, no advertisement to sit through, and no
> connection required. Ever.
>
> Every puzzle is generated on your device and guaranteed to be solvable by
> logic alone — never by guessing. The four difficulties are defined by the
> technique each one needs rather than by how many digits are missing, so
> "hard" means the same thing today as it did last week.
>
> HINTS THAT TEACH
> Stuck? Ask for a nudge and it names the technique in play. Ask again and it
> shows you where to look. Only the last step gives the answer away, so a hint
> leaves you better at Sudoku than it found you.
>
> A PUZZLE EVERY DAY
> Everyone gets the same daily puzzle, and solving it builds a streak. Miss a
> day and you can still play it later — the calendar keeps every one.
>
> MADE FOR IPHONE AND IPAD
> A full-size board on both, with keyboard support on iPad. Add a widget to see
> whether today's puzzle is still waiting without opening the app.
>
> EVERYTHING ELSE
> • Pencil marks, with optional auto-fill
> • Undo and redo, mistake highlighting you can turn off
> • Type in a puzzle from a newspaper, and it will tell you how hard it is
> • Share any puzzle as a link — the link *is* the puzzle, so no server is
>   involved
> • Statistics, achievements, and a year of your solving at a glance
> • Full VoiceOver support, Dynamic Type, and Reduce Motion
>
> No accounts. No advertisements. No tracking. No data collected — there is no
> server for it to be sent to.

## Keywords

`sudoku,puzzle,offline,logic,daily,numbers,brain,solver,hints,no ads`

100 characters is the limit and repeating a word already in the name or subtitle
is wasted space, so "cake" and "teaches" are deliberately absent.

## Support and marketing URLs

| Field | Value |
|---|---|
| Support URL | `https://sudoku.andcake.dev` |
| Marketing URL | `https://sudoku.andcake.dev` |
| Privacy policy URL | `https://sudoku.andcake.dev/privacy` |

**The privacy policy page has to exist before submission.** It is a required
field, and this app's policy is three sentences: nothing is collected, nothing
leaves the device, there is no server.

## App privacy answers

App Store Connect asks these separately from `PrivacyInfo.xcprivacy`, and the
two must agree or review will say so.

| Question | Answer |
|---|---|
| Do you collect data from this app? | **No** |
| Does the app use tracking? | **No** |

That single "No" is what makes the rest of the questionnaire disappear, and it
is true because there is no networking code in the app at all. See
`SudokuApp/Resources/PrivacyInfo.xcprivacy` for the manifest form of the same
claim, including the one required-reason API (`UserDefaults`, CA92.1).

## Review notes

> No account is needed and there is nothing to log in to. The app works with
> airplane mode on — please feel free to test it that way.
>
> The daily puzzle is generated from the date on the device, not fetched, so it
> works offline and is the same for every user on a given day.
>
> The widget shows the state of today's puzzle. It reads a small file the app
> writes into the shared App Group container and never accesses anything else.

## Screenshots

Required: **6.9" iPhone (1320×2868)** and, because the app ships universal
(`deviceFamily: [1, 2]`), **13" iPad (2064×2752)**. The App Store accepts one
set per device class and scales down, so those two sizes cover every device.

Five are captured in `screenshots/iphone-6.3/`, and they are the right *shots*:

| # | File | Screen | Caption |
|---|---|---|---|
| 1 | `1-home.png` | Home — daily, resume, the difficulty ladder | Every puzzle solvable by logic alone |
| 2 | `2-board.png` | A board mid-solve with pencil marks | Notes, hints and undo where you expect them |
| 3 | `3-hint.png` | A hint naming the technique | Hints that teach, not hints that tell |
| 4 | `4-settings.png` | Settings | It plays the way you want it to |
| 5 | `5-win.png` | The win card with achievements | Solved — and it remembers |

**They are the wrong size.** All five are 1206×2622 — the 6.3" iPhone 17 Pro,
which is what `scripts/screenshot.sh` picks by default and what the simulator's
own ⌘S produces on that device. App Store Connect wants 6.9", and a universal
app owes it a 13" iPad set too. Hence the folder per device class:

| Folder | Device | `DEVICE=` | Size | State |
|---|---|---|---|---|
| `iphone-6.3/` | iPhone 17 Pro | *(default)* | 1206×2622 | ✅ captured, optional |
| `iphone-6.9/` | iPhone 17 Pro Max | `"iPhone 17 Pro Max"` | 1320×2868 | ❌ **required** |
| `ipad-13/` | iPad Pro 13-inch | `"iPad Pro 13"` | 2064×2752 | ❌ **required** |

Every size above was verified against the actual simulator.

### Capturing a set

`scripts/screenshot.sh` builds through `xcodebuild`, so — like the upload — it
has to run outside the nono sandbox.

```bash
DEV="iPhone 17 Pro Max"
OUT=screenshots/iphone-6.9

DEVICE="$DEV" ./scripts/screenshot.sh $OUT/1-home.png     iphone -skipWelcome -inMemoryStore
DEVICE="$DEV" ./scripts/screenshot.sh $OUT/2-board.png    iphone -skipWelcome -inMemoryStore -startGame medium -prefill 38
DEVICE="$DEV" ./scripts/screenshot.sh $OUT/4-settings.png iphone -skipWelcome -inMemoryStore
DEVICE="$DEV" ./scripts/screenshot.sh $OUT/5-win.png      iphone -skipWelcome -inMemoryStore -startGame easy -prefill 0
```

Swap `DEV="iPad Pro 13"`, `iphone` → `ipad` and `OUT` for the iPad set.

Two of the five need a hand. `3-hint.png` requires tapping **Hint**, and
`4-settings.png` requires navigating to Settings — no launch argument opens
either, so take those with ⌘S in the simulator the script leaves running. That
is how the existing five were captured, and it is fine: this is a handful of
images a couple of times a year, not a pipeline worth building.

## What is not here, and why

Two things in P9-7 cannot be produced from this repository and are handed over
deliberately rather than half-done:

1. **The TestFlight build.** `xcodebuild archive` plus signing and upload.
   `xcodebuild` cannot run inside the nono sandbox at all (Xcode applies its own
   Seatbelt sandbox for SwiftPM manifest evaluation, and Seatbelt does not
   nest), so no archive can be produced here.
2. **The real screenshots.** They should come from a signed, properly built app
   with the compiled asset catalogue — not from the hand-linked bundle used for
   development checks in this sandbox.

## Provisioning — done

Registered in the developer portal against team `TQ86N6HVWY`:

| Identifier | Kind | App Groups |
|---|---|---|
| `group.dev.andcake.sudoku` | App Group | — |
| `dev.andcake.sudoku` | App ID (explicit) | enabled, 1 assigned |
| `dev.andcake.sudoku.widgets` | App ID (explicit) | enabled, 1 assigned |

Both App IDs were created explicitly rather than left to Xcode's automatic
signing. Xcode creates a missing App ID on first build, but does not reliably
enable App Groups *and* assign the group to it — and the failure mode is a
provisioning error that names the entitlement rather than the assignment, which
sends you looking in the wrong place. Enabling the capability is also not
enough on its own: the group has to be ticked in the App ID's **Configure**
sheet, which is what makes it read "Enabled App Groups (1)".
