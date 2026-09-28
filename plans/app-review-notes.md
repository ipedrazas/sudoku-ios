# App Review notes

The answer to the Guideline 2.1 "Information Needed" rejection of submission
`3adb3641-8e90-4250-beb0-000771ac5b82` (App Version 1.0, submitted 12 Aug 2026),
and — once accepted — the standing contents of the **App Review Information →
Notes** field in App Store Connect. It lives here rather than only in the web
form for the same reason `store-listing.md` does: a paragraph typed into a text
box is not reviewable and is lost the moment it is replaced.

Apple asked for seven things. The numbering below is theirs.

---

## 0. The short version, first

Reviewers open this app expecting the usual shape and find none of it, which is
most likely why the review stalled. Stated plainly, up front:

> Sudoku and Cake is a single-player Sudoku game that runs entirely on the
> device. There is **no account, no login, no in-app purchase, no subscription,
> no advertising, no user-generated content, and no network code of any kind** —
> the app contains no `URLSession`, no sockets and no third-party SDKs, so there
> is no server it could talk to. **Please test it with Airplane Mode on**;
> every feature works identically.
>
> There are no credentials to supply because there is nothing to sign in to.
> Tapping any difficulty on the first screen starts a playable puzzle
> immediately.

---

## 1. Screen recording

Apple wants a recording made on a physical device running the latest OS,
starting from launch, covering the typical flow, and explicitly including any
permission prompt.

The app has exactly one permission prompt (notifications) and none of the other
listed categories, so the recording must show:

| # | What to show | Why it is in the list |
|---|---|---|
| 1 | Tap the icon on the Home Screen; the welcome sheet appears; tap **Start playing** | Apple requires the recording to begin at launch |
| 2 | The home screen: Daily puzzle, Stats, the difficulty ladder (Gentle → Expert), any saved games | The core navigation, in one frame |
| 3 | Tap **Medium**; a board appears; enter several digits with the number pad | Proves the app is playable with no setup |
| 4 | Switch to pencil-mark mode, add notes, undo, redo | The main input modes |
| 5 | Tap **Hint** three times on one cell | The differentiating feature: hint 1 names the technique, hint 2 shows where to look, only hint 3 fills the cell |
| 6 | Finish a puzzle (start a **Gentle** one if time matters) and let the win card appear | Shows completion, timing and achievements |
| 7 | Open **Daily puzzle**, then the calendar of past days | Shows the daily is generated from the date, not fetched |
| 8 | On the Daily screen, switch the **streak reminder** toggle on and let the iOS notification prompt appear; grant it, then switch it off again | **Required**: this is the app's only prompt for a device capability |
| 9 | Open **Settings** — theme, input mode, mistake highlighting, haptics, sound | Shows everything is a local preference |
| 10 | Open **Stats** — history, streaks, the year heatmap, achievements | Shows the data is local and player-owned |
| 11 | Share a puzzle from the game screen and show the generated link | Shows the link *is* the puzzle; no server is involved |
| 12 | Add the widget to the Home Screen and show today's status | Shows what the App Group entitlement is for |

Two things to do before recording, both of which pre-empt a second round:

- **Put the device in Airplane Mode for the whole recording** and let the
  control-centre indicator be visible. It answers "what does it talk to?"
  better than any sentence in this document can.
- Record on a physical device on the latest shipping iOS, not the simulator.
  Apple states the device requirement explicitly and a QuickTime capture of a
  simulator is recognisable.

The recording is uploaded as an attachment in the App Review reply. Keep it
under Apple's attachment limit; if the full flow runs long, cut steps 11–12 into
a second file rather than speeding the first one up.

## 2. Devices and operating systems tested

> Build 4 was run on an iPhone 17 Pro Max, iOS 27.0 (physical device).
>
> No physical iPad yet — iPad has been covered by simulators only. Add one here
> the day it is run on real hardware.

Alongside whatever physical devices are listed, the following is true and worth
stating:

> The app is built against the iOS 18.0 SDK deployment target and is universal
> (iPhone and iPad, `deviceFamily [1, 2]`). Automated tests run on both an
> iPhone and an iPad simulator on every change, and layouts are additionally
> checked at the largest accessibility Dynamic Type size.

## 3. What the app does, and for whom

> **What it is.** A Sudoku game with two things most Sudoku apps do not have.
>
> First, difficulty means something. Every puzzle is generated on the device and
> then *rated* by which solving technique it actually requires — naked single,
> hidden single, locked candidate, and so on — rather than by how many digits
> were removed. "Hard" therefore means the same thing this week as it did last
> week, and every puzzle is guaranteed to have exactly one solution reachable by
> logic alone, never by guessing.
>
> Second, the hints teach instead of telling. Asking for a hint names the
> technique that applies and the unit it applies in; asking again narrows it to
> the cells to look at; only the third and final step fills a digit in. A player
> who uses hints ends the puzzle knowing a technique they did not know before.
>
> Around those: a daily puzzle everyone shares, streaks and a calendar of past
> days, statistics and achievements, pencil marks with optional auto-fill, undo
> and redo, optional mistake highlighting, a manual entry screen that rates a
> puzzle copied from a newspaper, puzzle sharing by link, a Home Screen widget,
> and full VoiceOver, Dynamic Type and Reduce Motion support.
>
> **Who it is for.** People who already play Sudoku on paper or in another app
> and want a version that is honest about difficulty, works on a plane or the
> Underground, and does not want an account, a subscription or an advertisement
> between them and the puzzle. Rated 4+; nothing in it is unsuitable at any age.
>
> **The problem it solves.** Free Sudoku apps are generally funded by
> advertising and therefore need a connection, a session and an identity. This
> one is free because it costs nothing to run: there is no server, so there is
> nothing to fund and nothing to collect.

## 4. Setting up and reaching every feature

> No setup, no credentials, no sample files. The app is fully functional from
> first launch with no network connection.
>
> | Feature | How to reach it |
> |---|---|
> | Play a puzzle | Tap any difficulty on the home screen (Gentle, Easy, Medium, Hard, Expert) |
> | Pencil marks | The pencil button in the control bar under the board |
> | Hints | The **Hint** button; tap it repeatedly on the same puzzle to see all three levels |
> | Undo / redo | The arrows in the control bar |
> | Daily puzzle | **Daily puzzle** on the home screen; the calendar icon there opens past days |
> | Streak reminder (the only permission prompt) | On the Daily screen, switch on the reminder toggle. iOS asks for notification permission. Declining leaves the whole app usable — the toggle simply returns to off |
> | Statistics and achievements | **Stats** on the home screen |
> | Enter a puzzle by hand | **Import a puzzle** on the home screen; type in the digits and the app rates the difficulty |
> | Share a puzzle | The **Share** button on the game screen. The link (`sudokuandcake://…`) *encodes the puzzle itself* in about 46 characters, so opening it on another device with the app installed loads that exact puzzle. Nothing is uploaded and no server resolves the link |
> | Widget | Long-press the Home Screen → add the "Sudoku and Cake" widget. It shows whether today's daily is done |
> | Settings | **Settings** on the home screen — theme, input mode, mistake highlighting, sound, haptics |
> | Spanish | Change the device or app language to Spanish; the app, engine copy and widget are all fully translated |

## 5. External services, tools and platforms

> **None.** This is not a shorthand for "none that collect data" — the app makes
> no network requests at all, and there is no code in it capable of making one.
>
> - No data providers: every puzzle is generated on the device by the app's own
>   generator, including the daily one.
> - No authentication service: there are no accounts.
> - No payment processor: the app is free with no in-app purchases.
> - No AI or machine-learning service: the hint engine is a deterministic
>   constraint solver — the same technique rater that grades the puzzles, run
>   backwards — not a model, and nothing is sent anywhere to produce a hint.
> - No analytics, crash-reporting, attribution or advertising SDK.
> - **No third-party dependencies whatsoever.** The app links Apple frameworks
>   only (SwiftUI, SwiftData, WidgetKit, UserNotifications, AVFoundation,
>   CoreHaptics, Swift Charts) plus one first-party Swift package in the same
>   repository, `SudokuKit`, which contains the game engine.
> - The only entitlement is an App Group (`group.dev.andcake.sudoku`), used for
>   exactly one thing: a small JSON file the app writes and the widget reads so
>   the widget can show today's status without launching the app.
> - The only data stored is on the device — game state in SwiftData, preferences
>   in `UserDefaults`. `PrivacyInfo.xcprivacy` declares one required-reason API
>   (`UserDefaults`, CA92.1) and no collected data types, which matches the "we
>   do not collect data" answer in the App Privacy questionnaire.

## 6. Regional differences

> The app behaves identically in every region. Nothing is geo-gated, no feature
> is enabled or disabled by country or store front, and there is no
> region-specific content, pricing or availability logic — there is no server
> that could apply any.
>
> The only regional variation is language: the app ships English and Spanish and
> follows the device's language setting. Both languages have complete
> translations of the app, the engine's hint and achievement copy, and the
> widget; a check in the build enforces that no string exists in one language
> and not the other.
>
> One deliberate detail, in case it looks like a difference: the daily puzzle is
> derived from the **UTC** date rather than the local one, so every player in
> the world is solving the same puzzle on the same calendar day regardless of
> time zone.

## 7. Regulated industry and third-party material

> Neither applies.
>
> The app is a Sudoku game. It is not in a regulated industry — no gambling
> (there is no wagering, no virtual currency, no chance-based mechanic of any
> kind; puzzles are deterministic and solvable by logic), no finance, no health,
> no medical claims, no alcohol, no dating, no messaging.
>
> It contains no third-party protected material. Sudoku is a public-domain
> puzzle form, and no puzzle in the app is drawn from a book, a newspaper or any
> other published set: every one is generated on the device at the moment it is
> played. All artwork and audio is original and generated by scripts committed
> alongside the source — the app icon is drawn with CoreGraphics and the four
> sound effects are synthesised — so there is no licensed font, image, sound or
> data set anywhere in the bundle. The name "Sudoku and Cake" and the icon are
> our own.

---

## Before sending

The reply is complete except for §2, which cannot be answered from this
repository: it has to state the **physical** devices and OS versions this build
was actually run on. Answering it with anything other than the truth is worse
than answering it thinly — the reviewer's next step is to reproduce on one of
the devices named.

List each as model + iOS version, for example:

```
iPhone 16 Pro — iOS 26.1
iPad Air (M2) — iPadOS 26.1
```

At least one iPhone and one iPad, since the app ships as universal and claims
both. If the app has only ever run on a simulator, run it on a device first —
the recording Apple asked for requires one anyway.
