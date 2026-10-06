# App Review: reply to the Guideline 4.3(a) rejection

Submission `3adb3641-8e90-4250-beb0-000771ac5b82`, version 1.0 (4), reviewed
6 Oct 2026 on an iPad Air 11-inch (M3). Rejected under 4.3(a) Spam: "shares a
similar binary, metadata, and/or concept as apps submitted ... by other
developers".

The 2.1 information request is closed. This is a different objection, and it is
almost certainly about the *concept*: no code here is shared with anyone else,
so the binary and assets cannot match another developer's. Sudoku is one of the
most crowded categories on the store, and 4.3(a) is the usual response to one
more entry in it. The answer is to show what this app does that the others do
not, with evidence, briefly. Do not argue about whether Sudoku is allowed.

---

## Reply (paste into App Review)

> Hello, and thank you for the review.
>
> We would like to clarify that Sudoku and Cake is not a template, a
> repackaged app or a reskin. It is our own work, written from scratch, and it
> is the only app we have submitted.
>
> **Original code and assets.** The app is a native Swift/SwiftUI port of our
> own web game, Sudoku and Cake (https://sudoku.andcake.dev), which we also
> wrote. It contains no third-party code at all: it links only Apple frameworks
> and our own game engine. The puzzle generator, solver and difficulty rater
> are ours. The icon is drawn in code with CoreGraphics and the sound effects
> are synthesised by our own scripts, so there is no purchased or shared asset
> anywhere in the bundle. We are happy to provide source access if it would
> help the review.
>
> **What it does that other Sudoku apps do not:**
>
> 1. **Difficulty is defined by technique, not by missing digits.** Every
>    puzzle is generated on the device and then rated by the hardest solving
>    technique it actually requires (naked single, hidden single, locked
>    candidates, and so on). "Hard" means the same thing every day, and every
>    puzzle is guaranteed to be solvable by logic alone, without guessing.
> 2. **Hints that teach.** The first hint names the technique that applies and
>    the row, column or box it applies in. The second shows which cells to look
>    at. Only the third fills in a digit. A player who uses hints learns the
>    technique rather than just receiving the answer. To see this, start any
>    puzzle and tap Hint three times.
> 3. **Rate a puzzle from a newspaper or book.** Import a puzzle on the home
>    screen lets the player type in any puzzle. The app checks that it has a
>    single solution and tells them which techniques it needs and how hard it
>    is.
> 4. **The share link is the puzzle.** Sharing produces a link of about 46
>    characters that encodes the puzzle itself. It opens the exact puzzle on
>    another device with no server involved.
> 5. **Fully offline, with nothing collected.** There is no network code in the
>    app, no account, no advertising and no analytics. Every feature, including
>    the daily puzzle shared by every player, works in Airplane Mode, because
>    the daily is derived from the date on the device rather than downloaded.
>
> It also has full VoiceOver support (the board describes in words what it
> shows in colour), Dynamic Type up to the largest accessibility sizes, a Home
> Screen widget, and complete English and Spanish localisation.
>
> We understand the App Store has many Sudoku games. We built this one because
> the ones we tried rated difficulty by how many digits were missing and gave
> hints that just filled in the answer. We would be grateful if you could look
> again with these features in mind, and we are glad to answer any questions or
> provide anything that would help.

---

## Before sending

- **Check "the only app we have submitted".** It has to be true of this
  developer account, and of any other account that has submitted a Sudoku
  app with this name or code. If it is not, take the sentence out.
- **Paste the new description from `store-listing.md`.** It now opens with
  the three-step hints and the technique rating rather than "no account, no
  ads", which every privacy-minded puzzle app says. Changing metadata does not
  need a new build.
- **Attach a short recording of the three-step hint** and the import rating
  screen. A reviewer judging "only minor differences" decides in seconds, and
  a recording shows the difference faster than prose.

## If the reply is not enough

1. **Appeal to the App Review Board** (developer.apple.com/contact/app-store/?topic=appeal).
   It is a different set of people from the original reviewer, and 4.3(a) is
   the rejection most often overturned there for an app that is genuinely
   original. Send the same text.
2. **Make the difference impossible to miss.** For example, a first-run screen
   that walks through one hint, or a technique guide reachable from the home
   screen. That is a new build and a change to the product, so decide it as a
   product decision rather than only as a review tactic.
3. **Do not resubmit unchanged** without replying first. The rejection warns
   that repeat submissions mean longer reviews and, eventually, the account.
