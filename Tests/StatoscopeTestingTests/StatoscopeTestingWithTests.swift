//
//  StatoscopeTestingWithTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

private final class SampleScope:
    Statostore,
    ObservableObject {
    let childDeptch: Int
    
    init(childDepth: Int) {
        self.childDeptch = childDepth
    }

    @Subscope var atChild: SampleScope?

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

final class StatoscopeTestingWithTests: XCTestCase {

    func testWithTestSyntax() throws {
        try SampleScope.GIVEN {
            SampleScope(childDepth: 0)
        }
        .WHEN(.navigateChild)
        .WITH(\.atChild)
        .THEN(\.childDeptch, equals: 1)
        .POP()
        .THEN(\.childDeptch, equals: 0)
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
        .THEN(\.childDeptch, equals: 3)
        // deptch 1
        .POP()
        .WITH(\.atChild)
        .THEN(\.childDeptch, equals: 1)
        // deptch 2
        .POP()
        .WITH(\.atChild?.atChild)
        .THEN(\.childDeptch, equals: 2)
        .runTest()
    }
}
