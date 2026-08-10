import SwiftUI

@main
struct SudokuAndCakeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var provider = PuzzleProvider()

    var body: some Scene {
        // WindowGroup rather than a single window: on iPad this gives multiple
        // puzzles side by side for free, which only stays free if session state
        // is never a global singleton.
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Persist the pool when the app leaves the foreground, so a cold
            // launch starts warm.
            if phase != .active {
                Task { await provider.suspend() }
            }
        }
    }
}
