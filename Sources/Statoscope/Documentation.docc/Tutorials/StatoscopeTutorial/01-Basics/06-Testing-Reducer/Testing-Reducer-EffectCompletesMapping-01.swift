func testEffectCompletesReplaysTheRealMapping() throws {
    try NewsFeedArticleReducer.Store.GIVEN(
        state: NewsFeedArticleReducer.State(id: "42")
    )
    .WHEN(.systemLoadedScope)
    .WHEN_EffectCompletes(FetchArticleTitleEffect.self, with: "Article 42")
    .THEN(\.state.loading, equals: false)
    .THEN(\.state.loadedTitle, equals: "Article 42")
    .runTest()
}
