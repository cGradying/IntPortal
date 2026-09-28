// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "tauri-plugin-glance",
  platforms: [.iOS(.v14)],
  products: [
    .library(name: "tauri-plugin-glance", type: .static, targets: ["tauri-plugin-glance"])
  ],
  dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api")
  ],
  targets: [
    .target(name: "tauri-plugin-glance", dependencies: [.byName(name: "Tauri")], path: "Sources")
  ]
)
