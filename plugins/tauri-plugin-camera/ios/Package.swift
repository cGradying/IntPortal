// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "tauri-plugin-camera",
  platforms: [.iOS(.v14)],
  products: [
    .library(name: "tauri-plugin-camera", type: .static, targets: ["tauri-plugin-camera"])
  ],
  dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api")
  ],
  targets: [
    .target(name: "tauri-plugin-camera", dependencies: [.byName(name: "Tauri")], path: "Sources")
  ]
)
