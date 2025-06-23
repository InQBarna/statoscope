import StatoscopeTesting

final class CloudCounterTest: XCTestCase {

    func testUserFlow() throws {

        var expectedNetworkRequest = URLRequest(url: try XCTUnwrap(URL(string: "http://statoscope.com")))
        expectedNetworkRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedNetworkRequest.httpMethod = "POST"
        expectedNetworkRequest.httpBody = try JSONEncoder().encode(DTO(count: 0))

        try CloudCounter.GIVEN {
            CloudCounter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        // Increment
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .THEN_EnquedEffect(Network.Effect<DTO>(request: expectedNetworkRequest))
        .WHEN(.networkPostCompleted(DTO(count: 1)))
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        .THEN { XCTAssertEqual($0.effects.count, 0) }
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
