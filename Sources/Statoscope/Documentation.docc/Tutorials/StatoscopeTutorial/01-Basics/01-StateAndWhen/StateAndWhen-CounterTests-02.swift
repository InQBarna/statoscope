import StatoscopeTesting

final class CounterTest: XCTestCase {

    func testUserFlow() throws {
        try Counter.GIVEN {
            Counter()
        }
    }

}
