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
