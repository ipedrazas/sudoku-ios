import Foundation
import SudokuKit
import Testing

@testable import SudokuApp

/// The contract between the app and the widget process.
///
/// Everything here is about a file one process writes and another reads, some
/// time later, possibly on a different day. The interesting cases are all
/// staleness: the widget cannot be told that midnight happened, so what it shows
/// then has to be a function of the snapshot and the clock, and that function is
/// what these tests pin down.
@Suite("Widget snapshot")
@MainActor
struct SnapshotTests {

    /// The publishing tests run against the real today, not a fixed date.
    ///
    /// A session stamps its own `finishedAt` from the wall clock, so a
    /// completion recorded during a test is always dated now. Publishing a
    /// snapshot "for the 3rd of March" while the completion says August would
    /// test a state the app cannot be in — and the streak, which is the number
    /// most worth getting right, would read 0 for a reason that is an artefact.
    private let today = Date()

    private func date(_ key: String) -> Date {
        DailyPuzzle.date(fromKey: key) ?? Date()
    }

    private var todayKey: String { DailyPuzzle.dateKey(for: today) }

    // MARK: - Publishing

    @Test("An untouched daily publishes as ready, with the grid but no progress")
    func untouchedDaily() async {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository)
        let puzzle = await library.ensureDaily(for: today)

        let status = SnapshotPublisher(repository: repository).status(now: today)

        #expect(status.dateKey == todayKey)
        #expect(status.standing == .ready)
        #expect(status.givens == puzzle.puzzle.digits())
        #expect(status.board == nil)
        #expect(status.displayBoard == puzzle.puzzle.digits())
        #expect(status.remainingCells == nil)
    }

    @Test("A daily in progress publishes the player's board and what is left")
    func dailyInProgress() async {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository, autosaveDelay: .milliseconds(1))
        let session = await library.daily(for: today)

        let cell = session.board.emptyCells[0]
        session.select(cell)
        session.input(session.puzzle.solution[cell])
        library.flush()

        let status = SnapshotPublisher(repository: repository).status(now: today)

        #expect(status.standing == .inProgress)
        #expect(status.board == session.board.digits())
        #expect(status.remainingCells == session.board.emptyCells.count)
        #expect(status.board != status.givens)
    }

    @Test("A solved daily publishes as completed, showing the finished grid")
    func solvedDaily() async {
        let repository = InMemoryGameRepository()
        let library = GameLibrary(repository: repository)
        let session = await library.daily(for: today)
        solve(session)

        let status = SnapshotPublisher(repository: repository).status(now: today)

        #expect(status.standing == .completed)
        #expect(status.isCompleted)
        #expect(status.board == session.puzzle.solution.digits())
        #expect(status.streak == 1)
        #expect(status.lastCompletedDateKey == todayKey)
    }

    @Test("A day with no stored puzzle still publishes, without a board")
    func noPuzzleYet() {
        let status = SnapshotPublisher(repository: InMemoryGameRepository()).status(now: today)

        #expect(status.standing == .ready)
        #expect(status.givens == nil)
        #expect(status.displayBoard == nil)
    }

    // MARK: - Staleness

    @Test("Yesterday's snapshot rolls over to a fresh day rather than lying")
    func rollsOverAtMidnight() {
        let yesterday = DailyStatus(
            dateKey: "2026-03-02",
            isCompleted: true,
            streak: 12,
            bestStreak: 12,
            lastCompletedDateKey: "2026-03-02",
            givens: String(repeating: "0", count: 81),
            board: String(repeating: "1", count: 81)
        )

        let today = yesterday.rolled(to: date("2026-03-03"))

        #expect(today.dateKey == "2026-03-03")
        #expect(today.standing == .ready)
        // Yesterday's grid under today's date would be a widget showing a puzzle
        // that is not the one the app would open.
        #expect(today.displayBoard == nil)
        // Solved yesterday, not yet today: the streak stands, and stands to be
        // lost — which is precisely what the widget exists to say.
        #expect(today.streak == 12)
        #expect(today.bestStreak == 12)
    }

    @Test("A streak with no completion since the day before yesterday is gone")
    func streakExpires() {
        let stale = DailyStatus(
            dateKey: "2026-03-01",
            isCompleted: true,
            streak: 12,
            bestStreak: 30,
            lastCompletedDateKey: "2026-03-01"
        )

        let today = stale.rolled(to: date("2026-03-03"))

        #expect(today.streak == 0)
        // The best is history, and history does not expire.
        #expect(today.bestStreak == 30)
    }

    @Test("Today's snapshot survives its own rollover untouched")
    func todayIsNotRolled() {
        let today = DailyStatus(
            dateKey: "2026-03-03",
            isInProgress: true,
            remainingCells: 40,
            streak: 3,
            lastCompletedDateKey: "2026-03-02",
            givens: String(repeating: "0", count: 81),
            board: String(repeating: "2", count: 81)
        )

        #expect(today.rolled(to: date("2026-03-03")) == today)
    }

    @Test("A streak is alive on the day it was set and the day after")
    func streakGrace() {
        #expect(DailyStatus.isStreakAlive("2026-03-03", on: date("2026-03-03")))
        #expect(DailyStatus.isStreakAlive("2026-03-02", on: date("2026-03-03")))
        #expect(!DailyStatus.isStreakAlive("2026-03-01", on: date("2026-03-03")))
        #expect(!DailyStatus.isStreakAlive(nil, on: date("2026-03-03")))
    }

    @Test("The rollover instant is the next UTC midnight")
    func nextRollover() {
        let noon = date("2026-03-03").addingTimeInterval(12 * 3600)
        #expect(DailyStatus.nextRollover(after: noon) == date("2026-03-04"))
        // Exactly midnight belongs to the day that is starting, so the next
        // rollover is a full day away rather than zero seconds away — which
        // would be a timeline entry that expires the instant it is made.
        #expect(DailyStatus.nextRollover(after: date("2026-03-03")) == date("2026-03-04"))
    }

    // MARK: - The store

    @Test("A status survives the round trip through the container")
    func roundTrip() throws {
        let store = SnapshotStore(directory: try temporaryDirectory())
        let status = DailyStatus(
            dateKey: "2026-03-03",
            isInProgress: true,
            remainingCells: 17,
            elapsedSeconds: 402,
            streak: 4,
            bestStreak: 9,
            lastCompletedDateKey: "2026-03-02",
            givens: String(repeating: "0", count: 81),
            board: String(repeating: "3", count: 81),
            // On a whole second, because the file stores ISO-8601 and nothing
            // reading it cares about milliseconds. Written out so the equality
            // below is testing the encoding, not the clock.
            updatedAt: Date(timeIntervalSince1970: 1_772_150_400)
        )

        #expect(store.write(status))
        #expect(store.read() == status)
    }

    @Test("Without a container, writing fails quietly and reading finds nothing")
    func noContainer() {
        let store = SnapshotStore(directory: nil)

        #expect(!store.write(.empty()))
        #expect(store.read() == nil)
        // The case that happens on every CODE_SIGNING_ALLOWED=NO build and in
        // every test bundle. It must be boring.
        store.clear()
    }

    @Test("Rubbish in the container reads as no snapshot rather than a crash")
    func corruptFile() throws {
        let directory = try temporaryDirectory()
        let store = SnapshotStore(directory: directory)
        #expect(store.write(.empty()))

        // swiftlint:disable:next force_unwrapping
        try Data("not json".utf8).write(to: store.fileURL!)

        #expect(store.read() == nil)
    }

    // MARK: - Helpers

    private func temporaryDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "snapshot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Fills the board from the solution, which is the only way to reach the
    /// completion path without playing a puzzle by hand.
    private func solve(_ session: GameSession) {
        for cell in session.board.emptyCells {
            session.select(cell)
            session.input(session.puzzle.solution[cell])
        }
    }
}
