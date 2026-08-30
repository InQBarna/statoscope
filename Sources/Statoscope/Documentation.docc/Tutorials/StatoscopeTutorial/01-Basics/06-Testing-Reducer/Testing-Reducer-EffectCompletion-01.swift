func testEffectCompletion() throws {
    let fixedDate = Date(timeIntervalSince1970: 1000)
    let expectedArticles = [
        ArticleDTO(id: "1", title: "Article 1"),
        ArticleDTO(id: "2", title: "Article 2")
    ]

    try NewsFeedReducer.Store.GIVEN(
        state: NewsFeedReducer.State()
    ) { $0
        .injectObject(DateProvider { fixedDate })
        .injectObject(PersistenceProvider(get: { [] }, set: { _ in }))
    }
    .WHEN(.systemLoadedScope)
    .THEN(\.state.loading, equals: true)
    .WHEN_OlderEffectCompletes(with: .networkDidFinish(expectedArticles))
    .THEN(\.state.loading, equals: false)
    .THEN(\.state.loadedArticles, equals: expectedArticles)
    .runTest()
}
