//
//  StatiscopeTestingSnapshot.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 25/11/24.
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
        case onAppear
    }

    func update(_ when: When) throws {
        switch when {
        case .navigateChild:
            atChild = SampleScope(childDepth: childDepth + 1)
        case .onAppear:
            XCTFail("we don't want on Appear to be called on snapshot method")
        }
    }
}

private struct SampleView: View {
    @ObservedObject var scope: SampleScope
    var body: some View {
        Text("I am at depth: \(scope.childDepth)")
            .onAppear { scope.send(.onAppear) }
        if let atChild = scope.atChild {
            SampleView(scope: atChild)
        }
    }
}

final class StatoscopeTestingSnapshot: XCTestCase {

    func testSnapshot() throws {
        let snapshotCalled = expectation(description: "snapshot called")
        snapshotCalled.assertForOverFulfill = false
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .configureViewSnapshot(self) {
            snapshotCalled.fulfill()
            return SampleView(scope: $0)
        }
        .WHEN(.navigateChild)
        .runTest()
        wait(for: [snapshotCalled], timeout: 2)
    }

    func testSnapshotNotCallingOnAppear() throws {
        let snapshotCalled = expectation(description: "snapshot called")
        snapshotCalled.assertForOverFulfill = false
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .configureViewSnapshot(self) {
            snapshotCalled.fulfill()
            return SampleView(scope: $0)
        }
        .THEN(\.childDepth, equals: 0)
        .runTest()
        wait(for: [snapshotCalled], timeout: 2)
    }

    func testSnapshotNotCallingOnAppearOnChildren() throws {
        let snapshotCalled = expectation(description: "snapshot called")
        snapshotCalled.assertForOverFulfill = false
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .configureViewSnapshot(self) {
            snapshotCalled.fulfill()
            return SampleView(scope: $0)
        }
        .WHEN(.navigateChild)
        .runTest()
        wait(for: [snapshotCalled], timeout: 2)
    }

    // KNOWN FAILING — discovered bug, intentionally not fixed here (TDD later, see
    // UNCOVERED_BY_UNIT_TESTS.md). `takeSnapshot()` (TestPlan+Snapshot.swift) calls
    // `self.snapshot?(sut, name)` directly instead of going through `StoreTestPlan.safeSnapshot`,
    // so it never sets the `takingSnapshot` flag that the middleware installed by `safeSnapshot`
    // relies on to block re-entrant events (like SwiftUI's `.onAppear`) during rendering. Every
    // *automatic* snapshot point (GIVEN, after each WHEN) goes through `safeSnapshot` and is
    // correctly protected; this explicit, manually-triggered snapshot step is not, even though
    // its whole purpose (per its doc/naming) is to behave the same way. SampleScope.update
    // deliberately XCTFails on `.onAppear` to catch exactly this.
    func testExplicitTakeSnapshot() throws {
        let snapshotCalled = expectation(description: "snapshot called")
        snapshotCalled.assertForOverFulfill = false
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .configureViewSnapshot(self) {
            snapshotCalled.fulfill()
            return SampleView(scope: $0)
        }
        .takeSnapshot(name: "explicit")
        .runTest()
        wait(for: [snapshotCalled], timeout: 2)
    }

    // TODO: Make WITH compatible with snapshot
    func DISABLED_testWithTestSnapshot() throws {
        let snapshotCalled = expectation(description: "snapshot called")
        snapshotCalled.assertForOverFulfill = false
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .configureViewSnapshot(self) {
            snapshotCalled.fulfill()
            return SampleView(scope: $0)
        }
        .WHEN(.navigateChild)
        .WITH(\.atChild)
        .THEN(\.childDepth, equals: 1)
        .POP()
        .THEN(\.childDepth, equals: 0)
        .runTest()
        wait(for: [snapshotCalled], timeout: 2)
    }

    func TODO_testWithTestSnapshotOnChild() throws {
        let snapshotCalled = expectation(description: "snapshot called")
        snapshotCalled.assertForOverFulfill = false
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .WITH(\.atChild)
        .configureViewSnapshot(self) {
            snapshotCalled.fulfill()
            return SampleView(scope: $0)
        }
        .THEN(\.childDepth, equals: 1)
        .POP()
        .THEN(\.childDepth, equals: 0)
        .runTest()
        wait(for: [snapshotCalled], timeout: 2)
    }
}
