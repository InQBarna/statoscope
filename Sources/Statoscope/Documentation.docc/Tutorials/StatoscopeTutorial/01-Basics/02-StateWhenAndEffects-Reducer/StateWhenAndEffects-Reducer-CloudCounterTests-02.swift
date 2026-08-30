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
