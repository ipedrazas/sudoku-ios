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
    ///
    /// `-skipWelcome` is the same idea for the onboarding sheet, which lives in
    /// `UserDefaults` rather than the store: without it these tests would pass
    /// on a simulator that had run the app before and fail on a fresh one.
    @MainActor
    private func launchApp(arguments: [String] = ["-inMemoryStore", "-skipWelcome"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Waits for a cell to stop reading as empty.
    ///
    /// Reading `.label` once is a read of whatever snapshot XCUITest last took,
    /// and `waitForExistence` returns from cache without refreshing it — so a
    /// digit that has been placed can still look absent. That failed this suite
    /// on a loaded runner while the identical build passed elsewhere. A
    /// predicate expectation re-queries until it agrees or the time is up.
    @MainActor
    private func waitUntilFilled(_ cell: XCUIElement, timeout: TimeInterval = 15, _ message: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (label ENDSWITH %@)", "empty"),
            object: cell
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: timeout),
            .completed,
            "\(message) — the cell reads '\(cell.label)'"
        )
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
        waitUntilFilled(filled, "the tapped cell should have taken the digit")
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

    /// The stats screen with nothing to show, which is the state most likely to
    /// crash: empty charts, empty aggregates, and a grid of achievements nobody
    /// has earned.
    @MainActor
    func testStatsScreenOpensWithNoHistory() {
        let app = launchApp()

        let stats = app.buttons["home.stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 30), "the home screen should offer stats")
        stats.tap()

        // Matched across element types: a container's identifier surfaces as
        // `other` or `staticText` depending on how SwiftUI collapses it, and
        // pinning the type here would be pinning an implementation detail.
        let empty = app.descendants(matching: .any).matching(identifier: "stats.empty").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 15), "a store with no history should say so")

        let achievements = app.descendants(matching: .any).matching(identifier: "stats.achievements").firstMatch
        XCTAssertTrue(achievements.exists, "achievements are listed even when none are earned")
    }

    /// Import and settings, which are both screens that can only be reached
    /// from the home list and both of which build a lot of view on appear.
    @MainActor
    func testImportAndSettingsOpen() {
        let app = launchApp()

        let importRow = app.buttons["home.import"]
        XCTAssertTrue(importRow.waitForExistence(timeout: 30), "the home screen should offer import")
        importRow.tap()

        XCTAssertTrue(
            app.buttons["import.cell.0"].waitForExistence(timeout: 15),
            "the entry grid should render"
        )
        // An empty grid cannot be played, and the screen has to say why rather
        // than just disabling the button.
        XCTAssertFalse(app.buttons["import.play"].isEnabled)
        let status = app.descendants(matching: .any).matching(identifier: "import.status").firstMatch
        XCTAssertTrue(status.exists, "the status should always be on screen")

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "the home screen should offer settings")
        settings.tap()
        XCTAssertTrue(
            app.switches["settings.highlightMistakes"].waitForExistence(timeout: 15),
            "settings should render"
        )
    }

    /// Phase 4's acceptance criterion, on a real device store: play, quit the
    /// app outright, come back, and find the game where it was left.
    ///
    /// This is the one test that cannot use `-inMemoryStore`, for the obvious
    /// reason — so it uses `-resetStore` on the first launch instead, and the
    /// second launch deliberately does not, because inheriting the first
    /// launch's state is the entire point.
    /// The welcome sheet is the first thing a new player sees, and the only
    /// screen in the app that can trap someone: it disables interactive
    /// dismissal, so if its button ever stopped working the app would be
    /// unusable from a fresh install and every other test here would still pass.
    @MainActor
    func testTheWelcomeSheetCanBeDismissed() {
        let app = launchApp(arguments: ["-inMemoryStore", "-forceWelcome"])

        let start = app.buttons["welcome.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "the welcome sheet should appear")
        start.tap()

        XCTAssertTrue(
            app.buttons["difficulty.easy"].waitForExistence(timeout: 30),
            "dismissing the welcome should leave the home screen"
        )
    }

    @MainActor
    func testAGameSurvivesBeingQuit() {
        let app = launchApp(arguments: ["-resetStore", "-skipWelcome"])

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

        // Everything except the welcome sheet, which is not store state and
        // would stand in front of the resume list this test is about.
        app.launchArguments = ["-skipWelcome"]
        app.launch()

        let resume = app.buttons["resume.0"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30), "the game should be offered for resuming")
        resume.tap()

        let restored = app.buttons[identifier]
        XCTAssertTrue(restored.waitForExistence(timeout: 30), "the board should come back")
        waitUntilFilled(restored, "the digit placed before quitting should still be there")
    }
}
