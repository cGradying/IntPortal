// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PUPSISPortal",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Quiz deck scheduling — FSRS-6 spaced repetition. This is the repo's
        // first SwiftPM dependency (see Core/Quiz/FSRSAdapter.swift for why
        // it's isolated to one file rather than spread through Quiz/).
        //
        // NOT open-spaced-repetition/swift-fsrs (the org's own package,
        // v5.0.0): confirmed by reading its source that FSRS.next(),
        // FSRSDefaults, and FSRSParameters.init are all internal, not
        // public — the whole scheduling surface is unreachable from outside
        // the module. bootuz/SwiftFSRS's FSRS<Card: FSRSCard> and
        // .schedule(card:at:rating:) are genuinely public and usable.
        .package(url: "https://github.com/bootuz/SwiftFSRS", from: "1.0.2"),
    ],
    targets: [
        .executableTarget(
            name: "PUPSISPortal",
            dependencies: [.product(name: "FSRS", package: "SwiftFSRS")],
            path: "Sources/PUPSISPortalApp"
        ),
        .testTarget(
            name: "PUPSISPortalTests",
            dependencies: ["PUPSISPortal"],
            path: "Tests/PUPSISPortalTests"
        )
    ]
)
