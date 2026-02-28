//
//  Tutorial03_Middleware.swift
//  Statoscope
//
//  Examples from Tutorial 03: Middleware
//

import Foundation
import StatoscopeTesting
import Statoscope
import XCTest

/// Tutorial 03: Middleware for logging and error handling
enum Tutorial03 {

    final class Counter: Statostore, ObservableObject {

        @Published var viewDisplaysTotalCount: Int = 0

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case errorCase  // Will throw an error
        }

        func update(_ when: When) throws {
            switch when {
            case .userTappedIncrementButton:
                viewDisplaysTotalCount += 1
            case .userTappedDecrementButton:
                viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
            case .errorCase:
                throw InvalidStateError()
            }
        }
    }

    final class MiddlewareTests: XCTestCase {

        func testMiddlewareInterceptsEvents() throws {
            var interceptedEvents: [Counter.When] = []

            let counter = Counter()
                .addMiddleWare { _, when, forward in
                    interceptedEvents.append(when)
                    try forward(when)
                }

            try Counter.GIVEN {
                counter
            }
            .WHEN(.userTappedIncrementButton)
            .WHEN(.userTappedDecrementButton)
            .THEN { _ in
                XCTAssertEqual(interceptedEvents.count, 2)
            }
            .runTest()
        }

        func testMiddlewareCanHandleErrors() throws {
            var errorsCaught: [Error] = []

            let counter = Counter()
                .addMiddleWare { _, when, forward in
                    do {
                        try forward(when)
                    } catch {
                        errorsCaught.append(error)
                    }
                }

            try Counter.GIVEN {
                counter
            }
            .WHEN(.errorCase)
            .THEN { _ in
                XCTAssertEqual(errorsCaught.count, 1)
                XCTAssertTrue(errorsCaught.first is InvalidStateError)
            }
            .runTest()
        }

        func testMiddlewareCanLogEvents() throws {
            var logs: [String] = []

            let counter = Counter()
                .addMiddleWare { _, when, forward in
                    logs.append("Event: \(when)")
                    try forward(when)
                }

            try Counter.GIVEN {
                counter
            }
            .WHEN(.userTappedIncrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 1)
            .THEN { _ in
                XCTAssertTrue(logs.contains("Event: userTappedIncrementButton"))
            }
            .runTest()
        }
    }
}
