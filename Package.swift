// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Statoscope",
    platforms: [
      .iOS(.v13),
      .macOS(.v12),
      .tvOS(.v13),
      .watchOS(.v6)
    ],
    products: [
        .library(
            name: "Statoscope",
            targets: ["Statoscope"]
        ),
        .library(
            name: "StatoscopeTesting",
            targets: ["StatoscopeTesting"]
        )
    ],
    dependencies: [
        // .package(url: "https://github.com/realm/SwiftLint", from: "0.0.0")
    ],
    targets: [
        .target(
            name: "Statoscope",
            path: "Sources/Statoscope"
            // plugins: [.plugin(name: "SwiftLintPlugin", package: "SwiftLint")]
        ),
        .target(
            name: "StatoscopeTesting",
            dependencies: ["Statoscope"],
            path: "Sources/StatoscopeTesting"
            // plugins: [.plugin(name: "SwiftLintPlugin", package: "SwiftLint")]
        ),
        .testTarget(
            name: "StatoscopeTests",
            dependencies: ["Statoscope", "StatoscopeTesting"])
    ]
)
