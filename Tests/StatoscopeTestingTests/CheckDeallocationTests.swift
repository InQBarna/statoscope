//
//  CheckDeallocationTests.swift
//  
//
//  Created by Sergi Hernanz on 30/1/24.
//

import Foundation
import Statoscope
@testable import StatoscopeTesting
import XCTest

// swiftlint:disable nesting
class CheckDeallocationTests: XCTestCase {

    enum SimpleParentChild {
        final class Parent: Statostore, Injectable, ObservableObject {
            typealias When = Void
            @Subscope var child: Child?
            let uuid: UUID = UUID()
            static var defaultValue: Parent = Parent()
            func update(_ when: Void) throws {
                child = Child {
                    // Retaining self
                    self.send(())
                }
            }
        }
        final class Child: Statostore, ObservableObject {
            typealias When = Void
            let someDelegateToRetainParent: () -> Void
            init(someDelegateToRetainParent: @escaping () -> Void) {
                self.someDelegateToRetainParent = someDelegateToRetainParent
            }
            @Superscope var parent: Parent
            func update(_ when: Void) throws { }
        }
    }

    func testSimpleParentChildAutoretainedFailsTest() throws {
        XCTExpectFailure("This should fail")
        try SimpleParentChild.Parent.GIVEN {
            SimpleParentChild.Parent()
        }
        .WHEN(())
        .runTest(assertRelease: true)
    }
}
// swiftlint:enable nesting
