import Foundation
import SudokuKit
import Testing

@testable import SudokuApp

/// The links widgets build and the app resolves.
///
/// These run against the same `DeepLink` type the widget extension compiles, so
/// a route renamed on one side and not the other fails here rather than becoming
/// a widget tap that opens the app at the home screen and does nothing — the
/// failure mode this type exists to prevent, and one no build error would catch.
@Suite("Deep links")
struct DeepLinkTests {

    @Test("every route survives being turned into a URL and back")
    func roundTrip() throws {
        for link in [DeepLink.daily, .calendar, .stats, .puzzle(code: "AQID")] {
            #expect(DeepLink(url: link.url) == link, "\(link.url) did not come back as itself")
        }
    }

    @Test("the routes are the URLs the widgets are built against")
    func urlShapes() {
        #expect(DeepLink.daily.url.absoluteString == "sudokuandcake://daily")
        #expect(DeepLink.calendar.url.absoluteString == "sudokuandcake://calendar")
        #expect(DeepLink.stats.url.absoluteString == "sudokuandcake://stats")
    }

    @Test("a shared puzzle link parses as a puzzle, in either form")
    func puzzleLinks() throws {
        // An empty grid: this is about the URL, and the smallest legal code is
        // the one least likely to fail for a reason that is not the URL.
        let grid = SudokuKit.Grid()
        let code = ShareCode.encode(grid)

        let custom = try #require(ShareCode.url(for: grid))
        let universal = try #require(ShareCode.universalLink(for: grid))

        #expect(DeepLink(url: custom) == .puzzle(code: code))
        // The Universal Link is not our scheme at all, which is exactly why the
        // puzzle case is matched through ShareCode rather than on the scheme.
        #expect(DeepLink(url: universal) == .puzzle(code: code))
    }

    @Test("a link we do not recognise is not a route")
    func rejectsUnknownLinks() throws {
        for string in [
            "sudokuandcake://elsewhere",
            "sudokuandcake://",
            "https://example.com/daily",
            "https://sudoku.ios.andcake.dev/",
            "mailto:someone@example.com",
        ] {
            let url = try #require(URL(string: string))
            #expect(DeepLink(url: url) == nil, "\(string) should not be a route")
        }
    }

    /// A code that parses as a link but not as a puzzle. The route is still a
    /// route — refusing it belongs to the decoder, not the URL — and the app
    /// arriving at the home screen is the intended outcome.
    @Test("a malformed code is still a puzzle route, and simply opens nothing")
    func malformedCode() throws {
        let url = try #require(URL(string: "sudokuandcake://p/not-a-code"))

        #expect(DeepLink(url: url) == .puzzle(code: "not-a-code"))
        #expect(PuzzleSharing.generatedPuzzle(from: "not-a-code") == nil)
    }
}
