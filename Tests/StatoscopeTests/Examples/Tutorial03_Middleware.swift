//
//  Tutorial03_Middleware.swift
//  Statoscope
//
//  Examples from Tutorial 03: Middleware
//

import Foundation
// @extract:begin 01-03-01-code-0001
// @extract:begin 01-03-01-code-0004
// @extract:begin 01-03-01-codeview-0002
// @extract:begin 01-03-01-codeview-0003
import Statoscope
// @extract:end 01-03-01-code-0001
// @extract:end 01-03-01-codeview-0002
// @extract:end 01-03-01-codeview-0003

func setupVerboseLevel() {
    StatoscopeLogger.logLevel = LogLevel.all
}
// @extract:begin 01-03-01-code-0001
// @extract:end 01-03-01-code-0004

enum Tutorial03 {

    final class Counter: Statostore, ObservableObject {

        @Published var viewDisplaysTotalCount: Int = 0

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case errorCase  // Will throw an error
        }

        func update(_ when: When) throws {
            // @extract:end 01-03-01-code-0001
            switch when {
            case .userTappedIncrementButton:
                viewDisplaysTotalCount += 1
            case .userTappedDecrementButton:
                viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
            case .errorCase:
                throw InvalidStateError()
            }
            // @extract:begin 01-03-01-code-0001
        }
        // @extract:end 01-03-01-code-0001
        // @extract:begin 01-03-01-code-0001
    }
}
// @extract:end 01-03-01-code-0001

import StatoscopeTesting
import XCTest

extension Tutorial03 {
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

        // @extract:begin 01-03-01-code-0005
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
        // @extract:end 01-03-01-code-0005
    }
}

// @extract:begin 01-03-01-codeview-0002
// @extract:begin 01-03-01-codeview-0003
import SwiftUI

extension Tutorial03 {
    
    static func sendCrashReport(error: any Error) { /* ... */ }

    private struct CounterView: View {

        @StateObject var model = Counter()
        // @extract:end 01-03-01-codeview-0002
            .addMiddleWare { store, when, forward in
                do {
                    print("WHEN: \(when)")
                    try forward(when)
                } catch {
                    Tutorial03.sendCrashReport(error: error) 
                }
            }
        // @extract:begin 01-03-01-codeview-0002

        var body: some View {
            VStack {
                Text("\(model.viewDisplaysTotalCount)")
                HStack {
                    Button("+") {
                        model.send(.userTappedIncrementButton)
                    }
                    Button("-") {
                        model.send(.userTappedDecrementButton)
                    }
                }
            }
        }
    }

}
// @extract:end 01-03-01-codeview-0002
// @extract:end 01-03-01-codeview-0003
