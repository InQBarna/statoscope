func testParentCreatesChildWithParameters() throws {
    try NewsFeedReducer.Store.GIVEN {
        NewsFeedReducer.Store(initialState: NewsFeedReducer.State())
    }
    .THEN(\.state.loadingFeatureToggles, equals: true)
    .THEN { scope in
        XCTAssertNil(scope.state.atList)
    }
    .WHEN(.systemLoadedScope)
    .WHEN_OlderEffectCompletes(with: .featureTogglesLoaded(favoritesEnabled: true))
    .THEN(\.state.loadingFeatureToggles, equals: false)
    .THEN { scope in
        XCTAssertNotNil(scope.state.atList)
        XCTAssertEqual(scope.state.atList?.favoritesEnabled, true)
    }
    .runTest()
}
