import Foundation
import os

/// The App Group file the app writes and the widget reads.
///
/// Compiled into both targets. One JSON file, written whole, read whole; no
/// `UserDefaults` suite, because the widget needs this while the device is
/// locked and a file lets the protection class be stated outright (below)
/// instead of inherited from whatever the defaults system decides.
struct SnapshotStore: Sendable {

    /// Settled in §12.2 of the implementation plan, and registered against the
    /// team in the developer portal. Both targets carry it as an entitlement;
    /// without it `containerURL` is nil and everything here degrades to a no-op.
    static let appGroup = "group.dev.andcake.sudoku"

    static let shared = SnapshotStore()

    /// Nil when there is no container — an unsigned simulator build, a target
    /// missing the entitlement, or a provisioning profile that has not caught up
    /// yet. Not an error case: the app still plays, the widget still renders its
    /// placeholder, and nothing anywhere has to branch on it.
    let directory: URL?

    private static let filename = "daily-status.json"

    init() {
        directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
    }

    /// For tests, which have no entitlement and no business writing into a real
    /// group container even if they did.
    init(directory: URL?) {
        self.directory = directory
    }

    var fileURL: URL? { directory?.appending(path: Self.filename) }

    private static let logger = Logger(subsystem: "dev.andcake.sudoku", category: "snapshot")

    // MARK: - Reading

    /// The stored status, or nil if there is not one that can be read.
    ///
    /// Every failure — no container, no file, unreadable, unparseable — is the
    /// same answer, because there is nothing the caller could usefully do
    /// differently and a widget that renders an error is worse than one that
    /// renders a placeholder.
    func read() -> DailyStatus? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.snapshot.decode(DailyStatus.self, from: data)
    }

    // MARK: - Writing

    /// Replaces the stored status.
    ///
    /// `.completeUntilFirstUserAuthentication` is load-bearing rather than
    /// cautious. The default protection class for a new file is
    /// `.completeUntilFirstUserAuthentication` on most paths but the App Group
    /// container is not one to guess about, and a Lock Screen widget renders
    /// with the device locked: under `.complete` the read fails, the widget
    /// falls back to its placeholder, and the bug only ever shows up on a locked
    /// phone — the one place it is hardest to notice and hardest to debug.
    @discardableResult
    func write(_ status: DailyStatus) -> Bool {
        guard let fileURL else { return false }
        do {
            let data = try JSONEncoder.snapshot.encode(status)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            // A snapshot that cannot be written costs the widget its freshness
            // and costs the player nothing. It is never worth interrupting a
            // game for, so it is logged and dropped.
            Self.logger.error("Could not write the widget snapshot: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// The pair, declared together rather than at each call site, because they only
// work as a pair: a date written ISO-8601 and read as a timestamp is a decode
// failure, which surfaces as "no snapshot" and gets blamed on the writer.

extension JSONEncoder {
    static var snapshot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var snapshot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
