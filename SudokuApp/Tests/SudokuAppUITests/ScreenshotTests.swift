import XCTest

/// Drives the app into states a launch-only screenshot cannot reach — a
/// selected cell, pencil marks, a conflict — and writes PNGs to a directory.
///
/// Off unless `SUDOKU_SCREENSHOT_DIR` is set, so it never runs in CI or a normal
/// test pass. It exists because behaviour tests cannot see a layout: six green
/// CI runs missed a board rendering at half width, and one screenshot caught it.
/// The same suite will produce the App Store captures in P9-7.
final class ScreenshotTests: XCTestCase {

    private var directory: String? {
        ProcessInfo.processInfo.environment["SUDOKU_SCREENSHOT_DIR"]
    }

    override nonisolated func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureGameStates() throws {
        // Skip, not fail: this is a capture tool, and its absence from a normal
        // test run is the expected case rather than a problem.
        try XCTSkipIf(directory == nil, "set TEST_RUNNER_SUDOKU_SCREENSHOT_DIR to capture")
        let directory = try XCTUnwrap(directory)

        let app = XCUIApplication()
        app.launchArguments = ["-startGame", "easy"]
        app.launch()

        XCTAssertTrue(app.buttons["cell.0"].waitForExistence(timeout: 30))

        // A selected empty cell, with the digit highlight that comes with it.
        let empty = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@", "cell.", "empty")
        ).firstMatch
        empty.tap()
        save(app, to: directory, named: "10-selected")

        // A placed digit.
        app.buttons["digit.5"].tap()
        save(app, to: directory, named: "11-placed")

        // Pencil marks: notes mode, then a few candidates.
        let nextEmpty = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@", "cell.", "empty")
        ).firstMatch
        nextEmpty.tap()
        app.buttons["control.notes"].tap()
        for digit in ["digit.1", "digit.4", "digit.7", "digit.9"] {
            app.buttons[digit].tap()
        }
        save(app, to: directory, named: "12-notes")

        // A hint, at its first level.
        app.buttons["control.notes"].tap()
        app.buttons["control.hint"].tap()
        XCTAssertTrue(app.staticTexts["hint.text"].waitForExistence(timeout: 5))
        save(app, to: directory, named: "13-hint")
    }

    @MainActor
    private func save(_ app: XCUIApplication, to directory: String, named name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? data.write(to: url)
    }
}
