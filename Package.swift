// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Statoscope",
    platforms: [
      .iOS(.v14),
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
        // Depend on the Swift 5.9 release of SwiftSyntax
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", branch: "main")
    ],
    targets: [
        .target(
            name: "Statoscope",
            dependencies: [
              "StatoscopeMacros"
            ],
            path: "Sources/Statoscope"
            // plugins: [.plugin(name: "SwiftLintPlugin", package: "SwiftLint")]
        ),
        .testTarget(
            name: "StatoscopeTests",
            dependencies: [
                "Statoscope",
                "StatoscopeTesting"
            ],
            path: "Tests/StatoscopeTests"
        ),
        .target(
            name: "StatoscopeTesting",
            dependencies: ["Statoscope"],
            path: "Sources/StatoscopeTesting"
            // plugins: [.plugin(name: "SwiftLintPlugin", package: "SwiftLint")]
        ),
        .testTarget(
            name: "StatoscopeTestingTests",
            dependencies: [
                "Statoscope",
                "StatoscopeTesting"
            ],
            path: "Tests/StatoscopeTestingTests"
        ),
        .macro(
            name: "StatoscopeMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/StatoscopeMacros"
        ),
        .testTarget(
          name: "StatoscopeMacrosTests",
          dependencies: [
            "StatoscopeMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
          ],
          path: "Tests/StatoscopeMacrosTests"
        )
    ]
)
