import Foundation
import SudokuKit

/// Somewhere in the app, named as a URL.
///
/// Compiled into both targets, because a widget's whole interaction model is one
/// tap and a URL: the widget builds these and the app resolves them. Two
/// hand-written string literals in two processes is exactly the arrangement
/// where a rename in one silently becomes a tap that does nothing in the other.
enum DeepLink: Equatable, Sendable {

    /// Today's puzzle: straight into the game, or the daily screen if it is
    /// already solved. Which one is the app's decision, not the link's.
    case daily

    /// The month grid, for picking a past day.
    case calendar

    case stats

    /// A puzzle carried whole in a share code, from a link someone sent.
    case puzzle(code: String)

    static let scheme = "sudokuandcake"

    var url: URL {
        switch self {
        case .daily: Self.url(host: "daily")
        case .calendar: Self.url(host: "calendar")
        case .stats: Self.url(host: "stats")
        // Built by `ShareCode` rather than here: the share sheet and the widgets
        // must produce byte-identical links, and there is one way to do that.
        case .puzzle(let code): URL(string: "\(Self.scheme)://p/\(code)") ?? Self.url(host: "daily")
        }
    }

    /// Parses a link, whichever shape it arrived in.
    ///
    /// A share code may also come as a Universal Link (§12.4), which is not our
    /// scheme at all — so the puzzle case is tried through `ShareCode`, which
    /// knows both forms, rather than by matching on the scheme here.
    init?(url: URL) {
        if let code = ShareCode.code(from: url) {
            self = .puzzle(code: code)
            return
        }

        guard url.scheme == Self.scheme else { return nil }
        switch url.host() {
        case "daily": self = .daily
        case "calendar": self = .calendar
        case "stats": self = .stats
        default: return nil
        }
    }

    private static func url(host: String) -> URL {
        // The force is over a string literal with no user input in it. If these
        // stopped parsing, every widget tap would be dead and no test would run
        // long enough to notice, so a crash in a preview is the cheaper failure.
        // swiftlint:disable:next force_unwrapping
        URL(string: "\(scheme)://\(host)")!
    }
}
