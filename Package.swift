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
        // In-app auto-update. SwiftPM's Package.swift ships as a binaryTarget
        // (a prebuilt XCFramework), not source — see Scripts/make_mac_app.sh
        // for how it gets embedded into the hand-rolled .app bundle Xcode
        // would otherwise do for us.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "PUPSISPortal",
            dependencies: [
                .product(name: "FSRS", package: "SwiftFSRS"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PUPSISPortalApp",
            resources: [
                .copy("Resources/notes-editor.bundle.js"),
                .copy("Resources/Fonts"),
            ],
            linkerSettings: [
                // Xcode injects this rpath automatically for regular apps;
                // a hand-built (non-Xcode) SwiftPM bundle must add it itself
                // or the app can't find Sparkle.framework in Contents/Frameworks
                // at launch. (Sparkle docs: "Add the framework to your project".)
                // Split into separate -Xlinker args — swiftc's linker driver
                // rejects one comma-joined "-Wl,-rpath,..." token.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "PUPSISPortalTests",
            dependencies: ["PUPSISPortal"],
            path: "Tests/PUPSISPortalTests"
        )
    ]
)
