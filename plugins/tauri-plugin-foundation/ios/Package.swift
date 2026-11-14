// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "tauri-plugin-foundation",
  platforms: [.iOS(.v14)],
  products: [
    .library(name: "tauri-plugin-foundation", type: .static, targets: ["tauri-plugin-foundation"])
  ],
  dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api")
  ],
  targets: [
    .target(name: "tauri-plugin-foundation", dependencies: [.byName(name: "Tauri")], path: "Sources")
  ]
)
