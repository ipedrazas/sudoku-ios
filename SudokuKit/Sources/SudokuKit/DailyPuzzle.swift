import Foundation

/// The daily puzzle: the same puzzle for everyone, on every device, with no
/// server involved.
///
/// The web app generates the daily once and stores it, keyed by a deterministic
/// slug (`slug.GenerateForDate`). With no backend, determinism has to come from
/// the generator itself: seed a `SeededRandom` from the date and the puzzle
/// falls out the same way every time, on every device, forever.
///
/// That "forever" is the whole contract. A player's daily history, their streak,
/// and any past date they revisit all depend on the 3rd of March generating the
/// same grid next year as it does today — which is why `SeededRandom` owns its
/// shuffle and bounded draw rather than trusting stdlib algorithms that carry no
/// stability guarantee.
public enum DailyPuzzle {
    /// Everyone plays the same rung, matching the web app's `dailyDifficulty`
    /// (`internal/server/server.go:320`).
    public static let difficulty: Difficulty = .medium

    /// UTC, so a daily rolls over at the same instant everywhere and two players
    /// in different time zones are never on different puzzles.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The seed for a date: seconds from the epoch to that date's UTC midnight.
    ///
    /// Same derivation as `slug.GenerateForDate` (`internal/slug/slug.go:68`),
    /// so the two implementations at least agree on what "a day" means.
    public static func seed(for date: Date) -> UInt64 {
        UInt64(bitPattern: Int64(utcMidnight(of: date).timeIntervalSince1970))
    }

    /// Midnight UTC on the day containing `date`.
    public static func utcMidnight(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// `"YYYY-MM-DD"` in UTC — the storage key for a daily.
    public static func dateKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parses a `"YYYY-MM-DD"` key back to its UTC midnight.
    public static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// Generates the daily for a date. Deterministic: same date, same puzzle.
    ///
    /// Generation is not cheap, so callers should cache the result — the app
    /// stores it in SwiftData keyed by `dateKey`. Nothing here caches, so this
    /// stays a pure function.
    public static func generate(for date: Date) -> GeneratedPuzzle {
        var rng = SeededRandom(seed: seed(for: date))
        return Generator.generate(difficulty, using: &rng)
    }

    /// The dailies from `start` up to and including `end`, oldest first.
    ///
    /// Used by the calendar, which offers every past day as playable — the seed
    /// makes history reproducible with nothing stored.
    public static func dateKeys(from start: Date, to end: Date) -> [String] {
        var keys: [String] = []
        var cursor = utcMidnight(of: start)
        let last = utcMidnight(of: end)
        while cursor <= last {
            keys.append(dateKey(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }
}
