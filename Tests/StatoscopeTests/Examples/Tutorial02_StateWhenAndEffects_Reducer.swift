//
//  Tutorial02_StateWhenAndEffects_Reducer.swift
//  Statoscope
//
//  Examples from Tutorial 02: State, When and Effects (Reducer Pattern)
//

import Foundation
// @extract:begin StateWhenAndEffects-Reducer-CloudCounter-01
// @extract:begin StateWhenAndEffects-Reducer-CloudCounter-02
// @extract:begin StateWhenAndEffects-Reducer-CloudCounter-03
// @extract:begin StateWhenAndEffects-Reducer-CloudCounter-04
@_spi(Internal) @testable import Statoscope
// @extract:end StateWhenAndEffects-Reducer-CloudCounter-01

/// Tutorial 02: CloudCounter with State, When and Effects using Reducer pattern
enum Tutorial02Reducer {

    // @extract:end StateWhenAndEffects-Reducer-CloudCounter-02
    // @extract:end StateWhenAndEffects-Reducer-CloudCounter-03
    // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-04
    enum Network {
        static func buildURLRequestPosting(dto: DTO) throws -> URLRequest {
            guard let url = URL(string: "http://statoscope.com") else {
                throw InvalidStateError()
            }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(dto)
            return request
        }
    }

    // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-01
    // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-02
    // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-03
    struct DTO: Codable, Equatable {
        let count: Int
    }

    @Reducer
    struct CloudCounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
            var viewShowsLoadingAndDisablesButtons: Bool = false
        }
        // @extract:end StateWhenAndEffects-Reducer-CloudCounter-02

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case networkPostCompleted(DTO)
        }
        // @extract:end StateWhenAndEffects-Reducer-CloudCounter-03

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            // @extract:end StateWhenAndEffects-Reducer-CloudCounter-04
            switch when {
            case .userTappedIncrementButton:
                state.viewDisplaysTotalCount = state.viewDisplaysTotalCount + 1
                state.viewShowsLoadingAndDisablesButtons = true
                try postNewValueToNetwork(newValue: state.viewDisplaysTotalCount, effectsState: &effectsState)

            case .userTappedDecrementButton:
                guard state.viewDisplaysTotalCount > 0 else {
                    return
                }
                state.viewDisplaysTotalCount = state.viewDisplaysTotalCount - 1
                state.viewShowsLoadingAndDisablesButtons = true
                try postNewValueToNetwork(newValue: state.viewDisplaysTotalCount, effectsState: &effectsState)

            case .networkPostCompleted(let remoteCounter):
                state.viewShowsLoadingAndDisablesButtons = false
                state.viewDisplaysTotalCount = remoteCounter.count
            }
            // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-04
        }

        private static func postNewValueToNetwork(newValue: Int, effectsState: inout EffectsState<When>) throws {
            // @extract:end StateWhenAndEffects-Reducer-CloudCounter-04
            effectsState.enqueue(
                AnyEffect {
                    let request = try Network.buildURLRequestPosting(dto: DTO(count: newValue))
                    let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                    return When.networkPostCompleted(resDTO)
                }
            )
            // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-04
        }
        // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-02
        // @extract:begin StateWhenAndEffects-Reducer-CloudCounter-03
    }
}
// @extract:end StateWhenAndEffects-Reducer-CloudCounter-02
// @extract:end StateWhenAndEffects-Reducer-CloudCounter-03
// @extract:end StateWhenAndEffects-Reducer-CloudCounter-04

// @extract:begin StateWhenAndEffects-Reducer-CloudCounterTests-02
import StatoscopeTesting
import XCTest

extension Tutorial02Reducer {
    final class CloudCounterTests: XCTestCase {

        func testBasicFlow() throws {
            try CloudCounterReducer.Store.GIVEN {
                CloudCounterReducer.Store(initialState: CloudCounterReducer.State())
            }
            .THEN(\.state.viewDisplaysTotalCount, equals: 0)
            .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
            // Increment
            .WHEN(.userTappedIncrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 1)
            .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: true)
            .WHEN(.networkPostCompleted(DTO(count: 1)))
            .THEN(\.state.viewDisplaysTotalCount, equals: 1)
            .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
            // Decrement
            .WHEN(.userTappedDecrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 0)
            .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: true)
            .WHEN(.networkPostCompleted(DTO(count: 0)))
            .THEN(\.state.viewDisplaysTotalCount, equals: 0)
            .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
            // Invalid decrement (already at 0, no effect triggered)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.state.viewDisplaysTotalCount, equals: 0)
            .runTest(assertNoPendingEffects: false)  // Effects are still running
        }
    }
}
// @extract:end StateWhenAndEffects-Reducer-CloudCounterTests-02
// @extract:end StateWhenAndEffects-Reducer-CloudCounter-01
