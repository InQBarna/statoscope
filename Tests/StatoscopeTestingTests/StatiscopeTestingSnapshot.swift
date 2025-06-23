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

#if canImport(UIKit)
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
#endif
}
