// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Statoscope",
    platforms: [
      .iOS(.v13),
      .macOS(.v10_15),
      .tvOS(.v13),
      .watchOS(.v6),
    ],
    products: [
        .library(
            name: "Statoscope",
            targets: ["Statoscope"]
        ),
        .library(
            name: "StatoscopeTesting",
            targets: ["StatoscopeTesting"]
        ),
    ],
    targets: [
        .target(
            name: "Statoscope",
            path: "Sources/Statoscope"
        ),
        .target(
            name: "StatoscopeTesting",
            dependencies: ["Statoscope"],
            path: "Sources/StatoscopeTesting"
        ),
        .testTarget(
            name: "StatoscopeTests",
            dependencies: ["Statoscope", "StatoscopeTesting"]),
    ]
)
