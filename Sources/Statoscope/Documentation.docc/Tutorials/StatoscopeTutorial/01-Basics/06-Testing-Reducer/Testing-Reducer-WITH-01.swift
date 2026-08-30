func testChildStoreInteractionsWithWITH() throws {
    try NewsFeedReducer.Store.GIVEN(
        state: NewsFeedReducer.State()
    )
    .WHEN(.navigateToChild(id: "42"))
    // Drop into the child store — all subsequent steps operate on Store<NewsFeedArticleReducer>
    .WITH(\.children.readingArticle)
    .THEN { articleStore in
        XCTAssertEqual(articleStore.state.id, "42")
        XCTAssertFalse(articleStore.state.isFavorite)
    }
    .WHEN(.systemLoadedScope)
    .THEN(\.state.loading, equals: true)
    .WHEN_OlderEffectCompletes(with: .articleLoaded(title: "Article 42"))
    .THEN(\.state.loading, equals: false)
    .THEN(\.state.loadedTitle, equals: "Article 42")
    .WHEN(.favorite)
    .THEN(\.state.isFavorite, equals: true)
    .WHEN(.favorite)
    .THEN(\.state.isFavorite, equals: false)  // Toggles back
    // POP back to the parent store to continue asserting on NewsFeedReducer
    .POP()
    .runTest()
}
