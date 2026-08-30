func testChildStoreInteractionsWithSubscopeKeypaths() throws {
    try NewsFeedReducer.Store.GIVEN(
        state: NewsFeedReducer.State()
    )
    .WHEN(.navigateToChild(id: "42"))
    // Keypath assertions into child store state via \.children.readingArticle?.state.*
    .THEN(\.children.readingArticle?.state.id, equals: "42")
    .THEN(\.children.readingArticle?.state.isFavorite, equals: false)
    // Send an event to the child store via its keypath — same API as non-Reducer
    .WHEN(\.children.readingArticle, .systemLoadedScope)
    .THEN(\.children.readingArticle?.state.loading, equals: true)
    // WHEN_OlderEffectCompletes cannot reach child store effects from the parent plan.
    // The child's effect lives in Store<NewsFeedArticleReducer>.effectsState, not the parent's.
    // Use WITH to descend into the child plan where WHEN_OlderEffectCompletes works:
    //   .WITH(\.children.readingArticle)
    //   .WHEN_OlderEffectCompletes(with: .articleLoaded(title: "Article 42"))
    //   .POP()
    .runTest(assertNoPendingEffects: false)
}
