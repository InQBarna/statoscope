import StatoscopeTesting

final class CounterTest: XCTestCase {

    func testUserFlow() throws {
        try Counter.GIVEN {
            Counter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
    }

}
