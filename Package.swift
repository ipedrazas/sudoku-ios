// swift-tools-version: 6.0
import PackageDescription

// SudokuKit is deliberately buildable without Xcode: the entire game engine —
// grid, solver, technique rater, generator, hint engine — is pure Swift with no
// UIKit and no platform SDK, so `swift test` on the command line is the primary
// development loop. Only the app shell needs Xcode.
let package = Package(
    name: "SudokuKit",
    // The kit owns the copy that teaches — hints, achievement names, difficulty
    // labels — so it carries its own translations. `.lproj` directories of
    // `.strings`, not a `.xcstrings` catalogue: SwiftPM *copies* a String
    // Catalogue into the resource bundle verbatim rather than compiling it, so
    // every lookup outside Xcode would silently fall back to the key. The older
    // format is the one that behaves identically under `swift test` and under
    // Xcode, and the command-line loop is the whole point of this target.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SudokuKit", targets: ["SudokuKit"])
    ],
    targets: [
        .target(
            name: "SudokuKit",
            path: "SudokuKit/Sources/SudokuKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SudokuKitTests",
            dependencies: ["SudokuKit"],
            path: "SudokuKit/Tests/SudokuKitTests",
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
