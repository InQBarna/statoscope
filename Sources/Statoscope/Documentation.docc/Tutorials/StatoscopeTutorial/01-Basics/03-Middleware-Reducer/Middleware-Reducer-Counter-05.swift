func testMiddlewareCanLogEvents() throws {
    var logs: [String] = []

    let counter = CounterReducer.Store(initialState: CounterReducer.State())
        .addMiddleWare { _, when, forward in
            logs.append("Event: \(when)")
            try forward(when)
        }

    try CounterReducer.Store.GIVEN {
        counter
    }
    .WHEN(.userTappedIncrementButton)
    .THEN(\.state.viewDisplaysTotalCount, equals: 1)
    .THEN { _ in
        XCTAssertTrue(logs.contains("Event: userTappedIncrementButton"))
    }
    .runTest()
}
