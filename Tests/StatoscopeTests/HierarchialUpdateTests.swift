//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 16/3/24.
//

import Foundation
import XCTest
@_spi(SCT) import Statoscope

// swiftlint:disable nesting
class HierarchialUpdateTests: XCTestCase {

    enum FulfilledSimpleParentChild {
        final class Parent: Statostore, Injectable, HierarchialScopeMiddleWare, ObservableObject {
            typealias When = Void
            @Subscope var child: Child?
            let uuid: UUID = UUID()
            let exp: XCTestExpectation
            let scopeUpdateExp: XCTestExpectation
            init(exp: XCTestExpectation,
                 updateSubscopeExp: XCTestExpectation,
                 childExp: XCTestExpectation) {
                self.exp = exp
                self.scopeUpdateExp = updateSubscopeExp
                self.child = Child(exp: childExp)
            }
            static var defaultValue: Parent = Parent(
                exp: XCTestExpectation(description: ""),
                updateSubscopeExp: XCTestExpectation(description: ""),
                childExp: XCTestExpectation(description: "")
            )
            func update(_ when: Void) throws {
                exp.fulfill()
            }
            func updateSubscope<When: Sendable>(_ subEffect: WhenFromSubscope<When>) throws {
                scopeUpdateExp.fulfill()
                try subEffect.subscope()._unsafeSendImplementation(subEffect.when)
            }
        }
        final class Child: Statostore, ObservableObject {
            typealias When = Void
            @Superscope var parent: Parent
            let exp: XCTestExpectation
            init(exp: XCTestExpectation) {
                self.exp = exp
            }
            func update(_ when: Void) throws {
                exp.fulfill()
            }
        }
    }

    func testChildParentUpdateSubscopeCalled() {
        let parentExp = expectation(description: "parent update called")
        parentExp.isInverted = true
        let updateSubscopeExp = expectation(description: "parent updateSubscope called")
        let childExp = expectation(description: "child update called")
        let sut = FulfilledSimpleParentChild.Parent(
            exp: parentExp,
            updateSubscopeExp: updateSubscopeExp,
            childExp: childExp
        )
        sut.child?.send(())
        waitForExpectations(timeout: 0.1)
    }

    func testParentUpdateSubscopeNotCalled() {
        let parentExp = expectation(description: "parent update called")
        let updateSubscopeExp = expectation(description: "parent updateSubscope called")
        let childExp = expectation(description: "child update called")
        childExp.isInverted = true
        let sut = FulfilledSimpleParentChild.Parent(
            exp: parentExp,
            updateSubscopeExp: updateSubscopeExp,
            childExp: childExp
        )
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
}
