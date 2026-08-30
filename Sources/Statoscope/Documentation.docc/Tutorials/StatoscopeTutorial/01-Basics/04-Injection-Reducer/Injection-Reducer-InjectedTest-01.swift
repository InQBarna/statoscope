func testInjectedLoggerIsCalledOnIncrement() throws {
    var capturedMessages: [String] = []

    try AuditedCounter.Store.GIVEN {
        AuditedCounter.Store(initialState: .init())
            .injectObject(AuditLogger { capturedMessages.append($0) })
    }
    .WHEN(.increment)
    .THEN(\.state.count, equals: 1)
    .THEN(\.state.lastMessage, equals: "increment: 0 → 1")
    .runTest()

    XCTAssertEqual(capturedMessages, ["increment: 0 → 1"])
}
