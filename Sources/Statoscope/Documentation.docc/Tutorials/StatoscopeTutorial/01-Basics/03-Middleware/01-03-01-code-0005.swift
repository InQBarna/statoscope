func testMiddlewareCanLogEvents() throws {
    var logs: [String] = []

    let counter = Counter()
        .addMiddleWare { _, when, forward in
            logs.append("Event: \(when)")
            try forward(when)
        }

    try Counter.GIVEN {
        counter
    }
    .WHEN(.userTappedIncrementButton)
    .THEN(\.viewDisplaysTotalCount, equals: 1)
    .THEN { _ in
        XCTAssertTrue(logs.contains("Event: userTappedIncrementButton"))
    }
    .runTest()
}
