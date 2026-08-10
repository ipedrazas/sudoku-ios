import XCTest

/// A deliberately thin smoke suite.
///
/// XCUITests are slow and flaky at volume, so this covers only what unit tests
/// cannot: that the app actually launches and that a tap reaches a real board.
/// Everything about *what* the board does is tested headlessly in
/// `GameSessionTests`.
///
/// Elements are addressed by accessibility **identifier**, never by label.
/// Labels are prose for VoiceOver and belong to the design; an earlier version
/// matched `buttons["Easy"]` and found nothing, because SwiftUI composes a
/// button's label from every `Text` inside it — that button reads "Easy,
/// scanning". Identifiers keep the tests from breaking every time the copy
/// changes.
final class SmokeTests: XCTestCase {

    // XCUIApplication is main-actor isolated under Swift 6 strict concurrency,
    // so the tests that drive it must be too. `setUp` stays nonisolated: it
    // overrides a nonisolated declaration, and changing that isolation is an
    // error rather than a choice.
    override nonisolated func setUp() {
        continueAfterFailure = false
    }

    /// A run must not inherit whatever the last one left in the store, or the
    /// home screen has an "In progress" section that no test put there.
    @MainActor
    private func launchApp(arguments: [String] = ["-inMemoryStore"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    func testLaunchesToTheDifficultyPicker() {
        let app = launchApp()

        XCTAssertTrue(
            app.buttons["difficulty.easy"].waitForExistence(timeout: 30),
            "the app should launch to a difficulty picker"
        )
    }

    /// The tracer bullet, end to end: choose a difficulty, get a generated
    /// board, tap a cell, tap a digit, see it appear.
    @MainActor
    func testPlacingADigit() {
        let app = launchApp()

        let easy = app.buttons["difficulty.easy"]
        XCTAssertTrue(easy.waitForExistence(timeout: 30), "the difficulty picker should appear")
        easy.tap()

        // Wait for the board, then find a cell the player is allowed to fill.
        // Emptiness comes from the label because that is genuinely what is being
        // asked; which cell it is comes from the identifier.
        XCTAssertTrue(
            app.buttons["cell.0"].waitForExistence(timeout: 30),
            "the board should render after choosing a difficulty"
        )

        let emptyCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@", "cell.", "empty")
        ).firstMatch
        XCTAssertTrue(emptyCell.exists, "a generated puzzle should have empty cells")

        let identifier = emptyCell.identifier
        emptyCell.tap()

        let five = app.buttons["digit.5"]
        XCTAssertTrue(five.waitForExistence(timeout: 10), "the number pad should be on screen")
        five.tap()

        // Same cell, addressed by identifier, should no longer read as empty.
        let filled = app.buttons[identifier]
        XCTAssertTrue(filled.waitForExistence(timeout: 10))
        XCTAssertFalse(
            filled.label.hasSuffix("empty"),
            "the tapped cell should have taken the digit, but reads '\(filled.label)'"
        )
    }

    /// The daily, end to end: it is generated on demand, so this is also the
    /// only check that the push into a freshly generated puzzle works.
    @MainActor
    func testPlayingTheDaily() {
        let app = launchApp()

        let daily = app.buttons["home.daily"]
        XCTAssertTrue(daily.waitForExistence(timeout: 30), "the home screen should offer the daily")
        daily.tap()

        let play = app.buttons["daily.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "the daily screen should offer a game")
        play.tap()

        XCTAssertTrue(
            app.buttons["cell.0"].waitForExistence(timeout: 30),
            "the daily should generate and render"
        )
    }

    /// Phase 4's acceptance criterion, on a real device store: play, quit the
    /// app outright, come back, and find the game where it was left.
    ///
    /// This is the one test that cannot use `-inMemoryStore`, for the obvious
    /// reason — so it uses `-resetStore` on the first launch instead, and the
    /// second launch deliberately does not, because inheriting the first
    /// launch's state is the entire point.
    @MainActor
    func testAGameSurvivesBeingQuit() {
        let app = launchApp(arguments: ["-resetStore"])

        let easy = app.buttons["difficulty.easy"]
        XCTAssertTrue(easy.waitForExistence(timeout: 30), "the difficulty picker should appear")
        easy.tap()

        XCTAssertTrue(app.buttons["cell.0"].waitForExistence(timeout: 30), "the board should render")

        let emptyCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@", "cell.", "empty")
        ).firstMatch
        let identifier = emptyCell.identifier
        emptyCell.tap()
        app.buttons["digit.5"].tap()

        // Backgrounding is what flushes the pending autosave, so it has to
        // happen before the process goes away — as it does when a player
        // swipes the app out of the switcher.
        //
        // Waiting for the state rather than assuming it: pressing home only
        // *asks*, and on a loaded CI runner the app can still be foreground a
        // second later. Terminating in that window kills it before the save,
        // which failed this test once with a resume list that was empty for a
        // reason that had nothing to do with persistence.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            app.wait(for: .runningBackground, timeout: 30),
            "the app should reach the background, which is where the pending save is flushed"
        )
        app.terminate()

        app.launchArguments = []
        app.launch()

        let resume = app.buttons["resume.0"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30), "the game should be offered for resuming")
        resume.tap()

        let restored = app.buttons[identifier]
        XCTAssertTrue(restored.waitForExistence(timeout: 30), "the board should come back")
        XCTAssertFalse(
            restored.label.hasSuffix("empty"),
            "the digit placed before quitting should still be there, but the cell reads '\(restored.label)'"
        )
    }
}
