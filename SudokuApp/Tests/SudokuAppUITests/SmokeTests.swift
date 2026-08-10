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

    @MainActor
    func testLaunchesToTheDifficultyPicker() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.buttons["difficulty.easy"].waitForExistence(timeout: 30),
            "the app should launch to a difficulty picker"
        )
    }

    /// The tracer bullet, end to end: choose a difficulty, get a generated
    /// board, tap a cell, tap a digit, see it appear.
    @MainActor
    func testPlacingADigit() {
        let app = XCUIApplication()
        app.launch()

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
}
