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
        // Hot reload for `swift run` dev builds — edit a view, save, the
        // already-running app swaps it in with state intact, no relaunch.
        // Only wired into Views/ (see each file's `@ObserveInjection`); a
        // no-op in a release build, see the `-interposable` note below.
        .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.5.2"),
        // MLX runtime for Qwen3.5 on Apple Silicon — see
        // .claude/plans/qwen3-5-0-8b-mlx-mlx-1-2gb-256k-effervescent-panda.md.
        // Stage-1 checkpoint: does this even resolve under our tools-version.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        // Adapts a local directory's tokenizer files into mlx-swift-lm's
        // `Tokenizer`/`TokenizerLoader` protocols (`Core/MLXBackend.swift`) —
        // BPE + chat-template parsing is exactly what this HF-maintained
        // package already does; not worth reimplementing.
        .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "PUPSISPortal",
            dependencies: [
                .product(name: "FSRS", package: "SwiftFSRS"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Inject", package: "Inject"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
                .product(name: "Transformers", package: "swift-transformers"),
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
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                // Inject's own requirement for a plain SwiftPM/command-line
                // build (no Xcode project managing this): forces every
                // symbol to resolve indirectly through the dynamic linker,
                // which is what lets InjectionIII swap a recompiled file's
                // code into the already-running process. Debug only —
                // `-interposable` disables dead-stripping and meaningfully
                // slows startup, and `make_mac_app.sh`/CI always build
                // `-c release`, so shipped builds never carry this.
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "PUPSISPortalTests",
            dependencies: ["PUPSISPortal"],
            path: "Tests/PUPSISPortalTests"
        )
    ]
)
