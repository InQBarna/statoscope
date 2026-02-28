import StatoscopeTesting
import XCTest

extension Tutorial0101 {

    final class CounterTests: XCTestCase {

        func testBasicCounterFlow() throws {
            try Counter.GIVEN {
                Counter()
            }
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .WHEN(.userTappedIncrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 1)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 0)  // Can't go below 0
        }
    }
}
