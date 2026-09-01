// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PriorsEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PriorsEngine", targets: ["PriorsEngine"]),
    ],
    targets: [
        // Pure logic. No SwiftUI, no SpriteKit, no UIKit — if an import of one
        // appears here, the code is in the wrong repository (SPEC §12).
        .target(name: "PriorsEngine"),
        .testTarget(
            name: "PriorsEngineTests",
            dependencies: ["PriorsEngine"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
