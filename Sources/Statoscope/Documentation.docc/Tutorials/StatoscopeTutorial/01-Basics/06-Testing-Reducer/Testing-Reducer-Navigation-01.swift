func testNavigationCreatesChildStore() throws {
    try NewsFeedReducer.Store.GIVEN(
        state: NewsFeedReducer.State()
    )
    .THEN { store in
        XCTAssertNil(store.children.readingArticle)
    }
    .WHEN(.navigateToChild(id: "1"))
    .THEN { store in
        XCTAssertNotNil(store.children.readingArticle)
        XCTAssertEqual(store.children.readingArticle?.state.id, "1")
    }
    .WHEN(.navigateToChild(id: "2"))
    .THEN { store in
        XCTAssertEqual(store.children.readingArticle?.state.id, "2")
    }
    .runTest()
}
