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
}
