//
//  SampleScope.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 23/11/24.
//

import XCTest
import SwiftUI
@_spi(SCT) import Statoscope
import StatoscopeTesting

private final class SampleScope:
    Statostore,
    ObservableObject {
    let childDeptch: Int
    
    init(childDepth: Int) {
        self.childDeptch = childDepth
        self.atNonOptChild = NonOptSampleScope()
    }

    @Subscope var atChild: SampleScope?
    @Subscope var atNonOptChild: NonOptSampleScope

    enum When {
        case navigateChild
    }

    func update(_ when: When) throws {
        switch when {
        case .navigateChild:
            atChild = SampleScope(childDepth: childDeptch + 1)
        }
    }
}

private final class NonOptSampleScope: Statostore {
    enum When {
        case dummy
    }
    func update(_ when: When) throws { }
}

private struct SampleView: View {
    @ObservedObject var scope: SampleScope
    var body: some View {
        Text("I am at depth: \(scope.childDeptch)")
        if let atChild = scope.atChild {
            SampleView(scope: atChild)
        }
    }
}

final class StatoscopeTestingRunTests: XCTestCase {
    
    func testRunTestsForgotten() throws {
        XCTExpectFailure("GIVEN should fail if runTest is not called at the end")
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .THEN_NotNil(\.atChild)
    }
    
    func testRunTestsCalledTwice() throws {
        XCTExpectFailure("GIVEN should fail if runTest is called twice")
        let plan = StoreTestPlan {
            SampleScope(childDepth: 0)
        }
        try plan
            .WHEN(.navigateChild)
            .THEN_NotNil(\.atChild)
            .runTest()
        try plan.runTest()
    }

    func testRunTestsForgottenWithWith() throws {
        XCTExpectFailure("GIVEN should fail if runTest is not called at the end")
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .WITH(\.atChild)
        .THEN(\.childDeptch, equals: 1)
        .POP()
        .THEN(\.childDeptch, equals: 0)
    }
    
    func testRunTestsCalledOnWith() throws {
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .WITH(\.atChild)
        .THEN(\.childDeptch, equals: 1)
        .runTest()
    }
    
    func testRunTestsForgottenWithNonOptWith() throws {
        XCTExpectFailure("GIVEN should fail if runTest is not called at the end")
        SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WITH(\.atNonOptChild)
    }
    
    func testRunTestsCalledOnNonOptWith() throws {
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .WITH(\.atNonOptChild)
        .runTest()
    }

    func testRunTestsCalledOnFork() throws {
        XCTExpectFailure("GIVEN should fail if runTest is not called at the end")
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .FORK(.navigateChild) {
            let forked = try $0
                .THEN(\.atChild?.childDeptch, equals: 1)
            try forked.runTest()
            return forked
        }
        .WHEN(.navigateChild)
        .THEN(\.atChild?.childDeptch, equals: 1)
        .runTest()
    }
}
