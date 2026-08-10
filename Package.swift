// swift-tools-version: 6.0
import PackageDescription

// SudokuKit is deliberately buildable without Xcode: the entire game engine —
// grid, solver, technique rater, generator, hint engine — is pure Swift with no
// UIKit and no platform SDK, so `swift test` on the command line is the primary
// development loop. Only the app shell needs Xcode.
let package = Package(
    name: "SudokuKit",
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
