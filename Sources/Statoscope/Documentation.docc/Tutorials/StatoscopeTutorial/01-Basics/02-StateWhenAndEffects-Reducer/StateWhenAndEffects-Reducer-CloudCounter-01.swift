@_spi(Internal) @testable import Statoscope
    struct DTO: Codable, Equatable {
        let count: Int
    }

    @Reducer
    struct CloudCounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
            var viewShowsLoadingAndDisablesButtons: Bool = false
        }

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case networkPostCompleted(DTO)
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
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
        }

        private static func postNewValueToNetwork(newValue: Int, effectsState: inout EffectsState<When>) throws {
            effectsState.enqueue(
                AnyEffect {
                    let request = try Network.buildURLRequestPosting(dto: DTO(count: newValue))
                    let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                    return When.networkPostCompleted(resDTO)
                }
            )
        }
    }
}

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
