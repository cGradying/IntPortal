// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "tauri-plugin-download",
  platforms: [.iOS(.v14)],
  products: [
    .library(name: "tauri-plugin-download", type: .static, targets: ["tauri-plugin-download"])
  ],
  dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api")
  ],
  targets: [
    .target(name: "tauri-plugin-download", dependencies: [.byName(name: "Tauri")], path: "Sources")
  ]
)
