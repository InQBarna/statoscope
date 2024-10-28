//
//  MiddlewareTests.swift
//
//
//  Created by Sergi Hernanz on 14/3/24.
//

import Foundation
import XCTest
@_spi(SCT) import Statoscope

// swiftlint:disable nesting
class MiddlewareTests: XCTestCase {

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
        sut.addMiddleWare { _, when, closure in
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
        sut.addMiddleWare { _, _, _ in
            exp.fulfill()
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }

    func testTwoMiddlewaresCalled() {
        let sut = FulfilledUpdate(exp: expectation(description: "update called"))
        let exp = expectation(description: "middleware 1 called")
        let exp2 = expectation(description: "middleware 2 called")
        sut.addMiddleWare { _, when, closure in
            exp.fulfill()
            try closure(when)
        }
        sut.addMiddleWare { _, when, closure in
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
        sut.addMiddleWare { _, when, closure in
            exp.fulfill()
            try closure(when)
        }
        sut.addMiddleWare { _, _, _ in
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
        sut.addMiddleWare { _, _, _ in
            exp.fulfill()
        }
        sut.addMiddleWare { _, when, closure in
            exp2.fulfill()
            try closure(when)
        }
        sut.send(())
        waitForExpectations(timeout: 0.1)
    }
}
