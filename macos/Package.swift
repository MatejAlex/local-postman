// swift-tools-version:6.0
//
// Local Postman, native. Two targets on purpose:
//
// - PostmanCore holds everything that is not a view: the data model, variable
//   substitution, request resolution, the HTTP sender, the MCP client, storage
//   and formatting. It has no UI dependency, so it builds and its tests run on
//   Linux too, which is how it was written and checked.
// - LocalPostman is the SwiftUI app. It needs the macOS 26 SDK (Liquid Glass),
//   so it is only declared when this manifest is evaluated on a Mac.

import PackageDescription

var targets: [Target] = [
    .target(
        name: "PostmanCore",
        path: "Sources/PostmanCore"
    ),
    .testTarget(
        name: "PostmanCoreTests",
        dependencies: ["PostmanCore"],
        path: "Tests/PostmanCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "PostmanCore", targets: ["PostmanCore"]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "LocalPostman",
        dependencies: ["PostmanCore"],
        path: "Sources/LocalPostman",
        // The views are main-actor code throughout; Swift 5 mode keeps the
        // strict-concurrency diagnostics from drowning out real errors while
        // the UI is still moving. The core stays in Swift 6 mode.
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
)
products.append(.executable(name: "LocalPostman", targets: ["LocalPostman"]))
#endif

let package = Package(
    name: "LocalPostman",
    platforms: [.macOS("26.0")],
    products: products,
    targets: targets
)
