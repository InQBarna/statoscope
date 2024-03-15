//
//  MiddlewareTests.swift
//
//
//  Created by Sergi Hernanz on 14/3/24.
//

import Foundation
import XCTest
@testable import Statoscope

// swiftlint:disable nesting
class MiddlewareTests: XCTestCase {
    
    enum SimpleParentChild {
        final class Parent: Statostore, Injectable, ObservableObject {
            typealias When = Void
            @Subscope var child: Child? = Child()
            let uuid: UUID = UUID()
            static var defaultValue: Parent = Parent()
            func update(_ when: Void) throws { }
        }
        final class Child: Statostore, ObservableObject {
            typealias When = Void
            @Superscope var parent: Parent
            func update(_ when: Void) throws { }
        }
    }
    
    func testSimpleMiddlewareCalled() {
        let sut = SimpleParentChild.Parent()
        let exp = expectation(description: "middleware called")
        sut.addMiddleWare { state, when, closure in
            exp.fulfill()
            try closure(when)
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
    
    final class FulfilledUpdate: Statostore {
        typealias When = Void
        let uuid: UUID = UUID()
        let exp: XCTestExpectation
        init(exp: XCTestExpectation) {
            self.exp = exp
        }
        func update(_ when: Void) throws { 
            exp.fulfill()
        }
    }
    
    func testMiddlewareCalledAndCallsUpdate() {
        let sut = FulfilledUpdate(exp: expectation(description: "update called"))
        let exp = expectation(description: "middleware called")
        sut.addMiddleWare { state, when, closure in
            exp.fulfill()
            try closure(when)
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
    
    func testMiddlewareCalledAndDoesntCallUpdate() {
        let scopeExp = expectation(description: "update called")
        scopeExp.isInverted = true
        let sut = FulfilledUpdate(exp: scopeExp)
        let exp = expectation(description: "middleware called")
        sut.addMiddleWare { state, when, closure in
            exp.fulfill()
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
    
    func testTwoMiddlewaresCalled() {
        let sut = FulfilledUpdate(exp: expectation(description: "update called"))
        let exp = expectation(description: "middleware 1 called")
        let exp2 = expectation(description: "middleware 2 called")
        sut.addMiddleWare { state, when, closure in
            exp.fulfill()
            try closure(when)
        }
        sut.addMiddleWare { state, when, closure in
            exp2.fulfill()
            try closure(when)
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
    
    func testTwoMiddlewaresFirstCancelsNoMoreCalled() {
        let scopeExp = expectation(description: "update called")
        scopeExp.isInverted = true
        let sut = FulfilledUpdate(exp: scopeExp)
        let exp = expectation(description: "middleware 1 called")
        exp.isInverted = true
        let exp2 = expectation(description: "middleware 2 called")
        sut.addMiddleWare { state, when, closure in
            exp.fulfill()
            try closure(when)
        }
        sut.addMiddleWare { state, when, closure in
            exp2.fulfill()
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
    
    func testTwoMiddlewaresSecondCancelsNoMoreCalled() {
        let scopeExp = expectation(description: "update called")
        scopeExp.isInverted = true
        let sut = FulfilledUpdate(exp: scopeExp)
        let exp = expectation(description: "middleware 1 called")
        let exp2 = expectation(description: "middleware 2 called")
        sut.addMiddleWare { state, when, closure in
            exp.fulfill()
        }
        sut.addMiddleWare { state, when, closure in
            exp2.fulfill()
            try closure(when)
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
}
