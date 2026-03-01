//
//  Tutorial03_Middleware_Reducer.swift
//  Statoscope
//
//  Examples from Tutorial 03: Middleware (Reducer Pattern)
//

import Foundation
// @extract:begin Middleware-Reducer-Counter-01
// @extract:begin Middleware-Reducer-Counter-04
// @extract:begin Middleware-Reducer-CounterView-02
// @extract:begin Middleware-Reducer-CounterView-03
@_spi(Internal) @testable import Statoscope
// @extract:end Middleware-Reducer-Counter-01
// @extract:end Middleware-Reducer-CounterView-02
// @extract:end Middleware-Reducer-CounterView-03

private func setupVerboseLevel() {
    StatoscopeLogger.logLevel = LogLevel.all
}
// @extract:begin Middleware-Reducer-Counter-01
// @extract:end Middleware-Reducer-Counter-04

/// Tutorial 03: Middleware with Reducer pattern
enum Tutorial03Reducer {

    @Reducer
    struct CounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
        }

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case errorCase  // Will throw an error
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            // @extract:end Middleware-Reducer-Counter-01
            switch when {
            case .userTappedIncrementButton:
                state.viewDisplaysTotalCount += 1
            case .userTappedDecrementButton:
                state.viewDisplaysTotalCount = max(0, state.viewDisplaysTotalCount - 1)
            case .errorCase:
                throw InvalidStateError()
            }
            // @extract:begin Middleware-Reducer-Counter-01
        }
        // @extract:end Middleware-Reducer-Counter-01
        // @extract:begin Middleware-Reducer-Counter-01
    }
}
// @extract:end Middleware-Reducer-Counter-01

import StatoscopeTesting
import XCTest

extension Tutorial03Reducer {
    final class MiddlewareTests: XCTestCase {

        func testMiddlewareInterceptsEvents() throws {
            var interceptedEvents: [CounterReducer.When] = []

            let counter = CounterReducer.Store(initialState: CounterReducer.State())
                .addMiddleWare { _, when, forward in
                    interceptedEvents.append(when)
                    try forward(when)
                }

            try CounterReducer.Store.GIVEN {
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

            let counter = CounterReducer.Store(initialState: CounterReducer.State())
                .addMiddleWare { _, when, forward in
                    do {
                        try forward(when)
                    } catch {
                        errorsCaught.append(error)
                    }
                }

            try CounterReducer.Store.GIVEN {
                counter
            }
            .WHEN(.errorCase)
            .THEN { _ in
                XCTAssertEqual(errorsCaught.count, 1)
                XCTAssertTrue(errorsCaught.first is InvalidStateError)
            }
            .runTest()
        }

        // @extract:begin Middleware-Reducer-Counter-05
        func testMiddlewareCanLogEvents() throws {
            var logs: [String] = []

            let counter = CounterReducer.Store(initialState: CounterReducer.State())
                .addMiddleWare { _, when, forward in
                    logs.append("Event: \(when)")
                    try forward(when)
                }

            try CounterReducer.Store.GIVEN {
                counter
            }
            .WHEN(.userTappedIncrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 1)
            .THEN { _ in
                XCTAssertTrue(logs.contains("Event: userTappedIncrementButton"))
            }
            .runTest()
        }
        // @extract:end Middleware-Reducer-Counter-05
    }
}

// @extract:begin Middleware-Reducer-CounterView-02
// @extract:begin Middleware-Reducer-CounterView-03
import SwiftUI

extension Tutorial03Reducer {

    static func sendCrashReport(error: any Error) { /* ... */ }

    private struct CounterView: View {

        @StateObject var model = CounterReducer.Store(initialState: CounterReducer.State())
        // @extract:end Middleware-Reducer-CounterView-02
            .addMiddleWare { store, when, forward in
                do {
                    print("WHEN: \(when)")
                    try forward(when)
                } catch {
                    Tutorial03Reducer.sendCrashReport(error: error)
                }
            }
        // @extract:begin Middleware-Reducer-CounterView-02

        var body: some View {
            VStack {
                Text("\(model.state.viewDisplaysTotalCount)")
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
// @extract:end Middleware-Reducer-CounterView-02
// @extract:end Middleware-Reducer-CounterView-03
