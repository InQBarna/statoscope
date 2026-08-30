//
//  Tutorial01_StateAndWhen_Reducer.swift
//  Statoscope
//
//  Examples from Tutorial 01: State and When (Reducer Pattern)
//

import Foundation
// @extract:begin StateAndWhen-Reducer-Counter-01
// @extract:begin StateAndWhen-Reducer-Counter-02
// @extract:begin StateAndWhen-Reducer-Counter-03
// @extract:begin StateAndWhen-Reducer-Counter-04
// @extract:begin StateAndWhen-Reducer-Counter-05
@_spi(Internal) @testable import Statoscope
// @extract:end StateAndWhen-Reducer-Counter-01

/// Tutorial 01-01: Basic Counter with State and When using Reducer pattern
enum Tutorial01Reducer {

    @Reducer
    struct CounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
        }
        // @extract:end StateAndWhen-Reducer-Counter-02

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
        }
        // @extract:end StateAndWhen-Reducer-Counter-03

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            // @extract:end StateAndWhen-Reducer-Counter-04
            switch when {
            case .userTappedIncrementButton:
                state.viewDisplaysTotalCount += 1
            case .userTappedDecrementButton:
                state.viewDisplaysTotalCount = max(0, state.viewDisplaysTotalCount - 1)
            }
            // @extract:begin StateAndWhen-Reducer-Counter-04
        }
        // @extract:begin StateAndWhen-Reducer-Counter-02
        // @extract:begin StateAndWhen-Reducer-Counter-03
    }
}
// @extract:end StateAndWhen-Reducer-Counter-02
// @extract:end StateAndWhen-Reducer-Counter-03
// @extract:end StateAndWhen-Reducer-Counter-04
// @extract:end StateAndWhen-Reducer-Counter-05

// @extract:begin StateAndWhen-Reducer-CounterTests-02
// @extract:begin StateAndWhen-Reducer-CounterTests-04
import StatoscopeTesting
import XCTest

extension Tutorial01Reducer {
    final class CounterTests: XCTestCase {

        func testBasicCounterFlow() throws {
            try CounterReducer.Store.GIVEN {
                CounterReducer.Store(initialState: CounterReducer.State())
            }
            .THEN(\.state.viewDisplaysTotalCount, equals: 0)
            .WHEN(.userTappedIncrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 1)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 0)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 0)  // Can't go below 0
            .runTest()
        }

        func testMultipleIncrements() throws {
            try CounterReducer.Store.GIVEN {
                CounterReducer.Store(initialState: CounterReducer.State())
            }
            .WHEN(.userTappedIncrementButton)
            .WHEN(.userTappedIncrementButton)
            .WHEN(.userTappedIncrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 3)
            .runTest()
        }
    }
}
// @extract:end StateAndWhen-Reducer-CounterTests-02
// @extract:end StateAndWhen-Reducer-CounterTests-04

// @extract:begin StateAndWhen-Reducer-CounterView-01
import SwiftUI

extension Tutorial01Reducer {

    struct CounterView: View {

        @StateObject var store = CounterReducer.Store(initialState: CounterReducer.State())

        var body: some View {
            VStack {
                Text("\(store.state.viewDisplaysTotalCount)")
                HStack {
                    Button("+") {
                        store.send(.userTappedIncrementButton)
                    }
                    Button("-") {
                        store.send(.userTappedDecrementButton)
                    }
                }
            }
        }
    }
}
// @extract:end StateAndWhen-Reducer-CounterView-01
