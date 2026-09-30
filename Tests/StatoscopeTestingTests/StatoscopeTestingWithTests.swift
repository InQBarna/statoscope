//
//  StatoscopeTestingWithTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@_spi(SCT) import Statoscope
import StatoscopeTesting

private final class SampleScope:
    Statostore,
    ObservableObject {
    let childDepth: Int

    init(childDepth: Int) {
        self.childDepth = childDepth
    }

    @Subscope var atChild: SampleScope?

    enum When {
        case navigateChild
    }

    func update(_ when: When) throws {
        switch when {
        case .navigateChild:
            atChild = SampleScope(childDepth: childDepth + 1)
        }
    }
}

private final class WithParentScope: Statostore, Injectable, ObservableObject {
    enum When { case noop }
    var value: Int = 0
    static var defaultValue: WithParentScope { WithParentScope() }
    func update(_ when: When) throws { }
}

private final class WithChildScope: Statostore, ObservableObject {
    typealias When = Void
    @Superscope var parent: WithParentScope
    func update(_ when: Void) throws { }
}

final class StatoscopeTestingWithTests: XCTestCase {

    func testWithTestSyntax() throws {
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .WITH(\.atChild)
        .THEN(\.childDepth, equals: 1)
        .POP()
        .THEN(\.childDepth, equals: 0)
        .runTest()
    }

    func testWithTripleDepth() throws {
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .WHEN(\.atChild, .navigateChild)
        .WHEN(\.atChild?.atChild, .navigateChild)
        // deptch 3
        .WITH(\.atChild?.atChild?.atChild)
        .THEN(\.childDepth, equals: 3)
        // deptch 1
        .POP()
        .WITH(\.atChild)
        .THEN(\.childDepth, equals: 1)
        // deptch 2
        .POP()
        .WITH(\.atChild?.atChild)
        .THEN(\.childDepth, equals: 2)
        .runTest()
    }

    // MARK: - WITH() on a non-optional keyPath (WithStoreTestPlan, distinct from the
    // optional-keyPath WithOptStoreTestPlan every test above exercises)

    private static let parentKeyPath: KeyPath<WithChildScope, WithParentScope> = \.parent

    func testWithNonOptionalKeyPathNavigatesToSuperscope() throws {
        try WithChildScope.GIVEN {
            WithChildScope()
        }
        .WITH(Self.parentKeyPath)
        .THEN(\.value, equals: 0)
        .POP()
        .runTest()
    }

    func testWithNonOptionalKeyPathSupportsLinkedFork() throws {
        // buildLinkedFork on WithStoreTestPlan delegates to the parent plan's own
        // buildLinkedFork, then re-applies the same non-optional keyPath — exercised here via
        // plain FORK(), which calls buildLinkedFork() internally.
        try WithChildScope.GIVEN {
            WithChildScope()
        }
        .WITH(Self.parentKeyPath)
        .FORK(.noop) { plan in
            try plan.THEN(\.value, equals: 0)
        }
        .THEN(\.value, equals: 0)
        .POP()
        .runTest()
    }

    // MARK: - WITH() on an optional keyPath that's nil when the step actually runs

    func testWithOptionalKeyPathFailsWhenChildIsNilAtStepTime() throws {
        XCTExpectFailure("WITH() is expected to XCTFail when the optional child is nil")
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        // No .navigateChild sent — atChild is nil when this step runs.
        .WITH(\.atChild)
        .THEN(\.childDepth, equals: 999)
        .runTest()
    }
}
