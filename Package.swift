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
        // StatoscopeDemos intentionally has no product — it's internal-only demo/preview code
        // for working on Statoscope itself, never a dependency consumer apps link against.
    ],
    dependencies: [
        // .package(url: "https://github.com/realm/SwiftLint", from: "0.0.0")
        // Bumped from 509.0.0 (Swift 5.9-era, no typed-throws grammar support at all —
        // throws(SomeError) on an @EffectStruct function used to silently misparse the whole rest
        // of the signature, return type included) to 600.0.0 — the FIRST 6.0-era release, already
        // sufficient: confirmed ThrowsClauseSyntax is present as of 600.0.0 itself (checked
        // 600.0.0 through 603.0.0's generated syntax nodes directly), so this is the lowest floor
        // that picks up SE-0413 (typed throws) parsing support — not 604.x, which was only ever
        // an artifact of matching one particular dev machine's toolchain, not an actual
        // requirement. Raises this package's minimum toolchain to Xcode 16.0 (Swift 6.0).
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", branch: "main"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.2")
    ],
    targets: [
        .target(
            name: "Statoscope",
            dependencies: [
              "StatoscopeMacros"
            ],
            path: "Sources/Statoscope"
            // plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        // Internal-only demo/preview code (e.g. EnvironmentInjectionCrashDemo.swift) — kept out
        // of the "Statoscope" target so it's never part of a consumer app's build graph. No
        // product exposes this target; it exists purely so `swift test`/Xcode previews still
        // work when developing Statoscope itself.
        .target(
            name: "StatoscopeDemos",
            dependencies: ["Statoscope"],
            path: "Sources/StatoscopeDemos"
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
