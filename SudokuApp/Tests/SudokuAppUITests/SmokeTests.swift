import XCTest

/// A deliberately thin smoke suite.
///
/// XCUITests are slow and flaky at volume, so this covers only what unit tests
/// cannot: that the app actually launches and that a tap reaches a real board.
/// Everything about *what* the board does is tested headlessly in
/// `GameSessionTests`.
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
            app.buttons["Easy"].waitForExistence(timeout: 10),
            "the app should launch to a difficulty picker"
        )
    }

    /// The tracer bullet, end to end: choose a difficulty, get a generated
    /// board, tap a cell, tap a digit, see it appear.
    @MainActor
    func testPlacingADigit() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Easy"].waitForExistence(timeout: 10))
        app.buttons["Easy"].tap()

        // Cells are labelled "row R, column C, …" for VoiceOver, which also
        // makes them addressable here without test-only identifiers.
        let emptyCell = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH %@", "empty")
        ).firstMatch
        XCTAssertTrue(emptyCell.waitForExistence(timeout: 10), "the board should render empty cells")

        let label = emptyCell.label
        emptyCell.tap()

        let five = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "5,")
        ).firstMatch
        XCTAssertTrue(five.waitForExistence(timeout: 5), "the number pad should be on screen")
        five.tap()

        // The cell that read "…empty" should now report its value instead.
        XCTAssertFalse(
            app.buttons[label].exists,
            "the tapped cell should no longer be empty"
        )
    }
}
