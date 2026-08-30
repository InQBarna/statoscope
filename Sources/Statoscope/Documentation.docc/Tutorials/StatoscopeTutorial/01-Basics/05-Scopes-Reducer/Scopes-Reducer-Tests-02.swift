func testNavigationCreatesChildScope() throws {
    var initialState = NewsFeedListReducer.State()
    initialState.favoritesEnabled = true

    try NewsFeedListReducer.Store.GIVEN {
        NewsFeedListReducer.Store(initialState: initialState)
    }
    .THEN { scope in
        XCTAssertNil(scope.state.readingArticle)
    }
    .WHEN(.navigateFromListToChild(id: "1"))
    .THEN { scope in
        XCTAssertNotNil(scope.state.readingArticle)
        XCTAssertEqual(scope.state.readingArticle?.id, "1")
        XCTAssertEqual(scope.state.readingArticle?.favoritesEnabled, true)
    }
    .runTest()
}
