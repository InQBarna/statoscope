func testDefaultValueUsedWhenNoInjection() throws {
    // The defaultValue logger is silent; no crash, no side effect
    try AuditedCounter.Store.GIVEN {
        AuditedCounter.Store(initialState: .init())
        // No .injectObject() — uses AuditLogger.defaultValue
    }
    .THEN(\.state.count, equals: 0)
    .WHEN(.increment)
    .THEN(\.state.count, equals: 1)
    .WHEN(.increment)
    .THEN(\.state.count, equals: 2)
    .WHEN(.reset)
    .THEN(\.state.count, equals: 0)
    .runTest()
}
