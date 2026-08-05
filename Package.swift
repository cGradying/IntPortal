// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PUPSISPortal",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "PUPSISPortal",
            path: "Sources/PUPSISPortalApp"
        ),
        .testTarget(
            name: "PUPSISPortalTests",
            dependencies: ["PUPSISPortal"],
            path: "Tests/PUPSISPortalTests"
        )
    ]
)
