import SwiftUI

@main
struct SudokuAndCakeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var provider = PuzzleProvider()
    @State private var library = GameLibrary(repository: Self.repository)
    @State private var daily = DailyModel(repository: Self.repository)
    @State private var stats = StatsModel(repository: Self.repository)

    /// One store, shared. The library writes to it and the daily model reads
    /// from it; two containers over the same file would be two answers to every
    /// question.
    @MainActor private static let repository: any GameRepository = makeRepository()

    var body: some Scene {
        // WindowGroup rather than a single window: on iPad this gives multiple
        // puzzles side by side for free, which only stays free if session state
        // is never a global singleton.
        WindowGroup {
            RootView(provider: provider, library: library, daily: daily, stats: stats)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            // The last moment anything is guaranteed to run. The autosave
            // debounce is a second long and a backgrounded app may not get it,
            // so the pending write happens here instead.
            library.flush()
            // And the pool is persisted, so a cold launch starts warm.
            Task { await provider.suspend() }
        }
    }

    /// The SwiftData store, or an in-memory stand-in.
    ///
    /// Two reasons to fall back rather than crash. A store that cannot be opened
    /// — corrupt file, full disk, a schema from a newer build — should cost the
    /// history, not the app. And UI tests pass `-inMemoryStore` so a run starts
    /// from nothing and leaves nothing behind on the simulator.
    private static func makeRepository() -> any GameRepository {
        let arguments = ProcessInfo.processInfo.arguments
        guard let container = SwiftDataRepository.container(inMemory: arguments.contains("-inMemoryStore")) else {
            return InMemoryGameRepository()
        }

        let repository = SwiftDataRepository(container: container)
        // `-resetStore` empties the real store on launch. The UI test that
        // proves a game survives being force-quit cannot use `-inMemoryStore`,
        // for the obvious reason, so it needs some other way not to inherit
        // whatever the last run left behind.
        if arguments.contains("-resetStore") {
            try? repository.deleteAll()
        }
        return repository
    }
}
