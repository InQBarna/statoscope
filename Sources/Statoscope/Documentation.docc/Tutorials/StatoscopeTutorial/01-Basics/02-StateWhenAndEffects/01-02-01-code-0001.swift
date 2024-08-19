import StatoscopeTesting

struct DTO: Codable {
    let count: Int
}

final class CloudCounter: ScopeImplementation {
    var viewDisplaysTotalCount: Int = 0
    var viewShowsLoadingAndDisablesButtons: Bool = false
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
        case networkPostCompleted(DTO)
    }

    func update(_ when: When) throws {}
}

final class CloudCounterTest: XCTestCase {

    func testUserFlow() throws {
        try CloudCounter.GIVEN {
            CloudCounter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        // Increment
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .WHEN(.networkPostCompleted(DTO(count: 1)))
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        // Decrement
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .WHEN(.networkPostCompleted(DTO(count: 0)))
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        // Invalid decrement
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .runTest()
    }

}
