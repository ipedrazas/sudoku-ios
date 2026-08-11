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

Required: 6.9" iPhone and 13" iPad. The App Store accepts one set per device
class and scales down, so those two sizes cover every device.

| # | Screen | Caption |
|---|---|---|
| 1 | A board mid-solve | Solvable by logic alone |
| 2 | A hint sheet naming a technique | Hints that teach, not hints that tell |
| 3 | The daily and its streak | A new puzzle every day |
| 4 | Stats and the year heatmap | Watch yourself get better |
| 5 | Home Screen with widgets | Today's puzzle, at a glance |

Capture with `scripts/screenshot.sh`, which drives `ScreenshotTests` through
`xcodebuild` — so, like the upload, it has to be run outside the sandbox.

## What is not here, and why

Three things in P9-7 cannot be produced from this repository and are handed over
deliberately rather than half-done:

1. **The TestFlight build.** `xcodebuild archive` plus signing and upload.
   `xcodebuild` cannot run inside the nono sandbox at all (Xcode applies its own
   Seatbelt sandbox for SwiftPM manifest evaluation, and Seatbelt does not
   nest), so no archive can be produced here.
2. **The real screenshots.** They should come from a signed, properly built app
   with the compiled asset catalogue — not from the hand-linked bundle used for
   development checks in this sandbox.
3. **The App Group registration.** `group.dev.andcake.sudoku` has to exist in
   the developer portal against team `TQ86N6HVWY` before any signed build will
   provision, or the widgets will be permanently empty on device.
