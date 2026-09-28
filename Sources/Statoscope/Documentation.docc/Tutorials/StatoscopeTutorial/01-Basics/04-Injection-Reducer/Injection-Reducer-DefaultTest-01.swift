func testDefaultValuesUsedWhenNoInjection() throws {
    // No .injectObject() at all — DateProvider.defaultValue and
    // RealNetworkProvider.defaultValue are used automatically. Neither throws, unlike
    // dependencies.resolve() in NewsFeedListReducer.
    let store = NewsFeedStatusReducer.Store(initialState: .init())

    XCTAssertTrue(store.state.network is RealNetworkProvider)

    store.send(.checkNow)
    XCTAssertNotNil(store.state.lastCheckedAt)
}
